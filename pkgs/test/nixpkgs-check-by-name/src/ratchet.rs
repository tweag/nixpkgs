//! This module implements the ratchet checks, see ../README.md#ratchet-checks
//!
//! Each type has a `compare` method that validates the ratchet checks for that item.

use rowan::Language;
use rowan::NodeOrToken::Token;
use rowan::GreenToken;
use crate::NixFileStore;
use std::path::PathBuf;
use crate::nix_file::CallPackageArgumentInfo;
use crate::nixpkgs_problem::NixpkgsProblem;
use crate::structure;
use crate::validation::{self, Validation, Validation::Success};
use std::collections::HashMap;

/// The ratchet value for the entirety of Nixpkgs.
#[derive(Default)]
pub struct Nixpkgs {
    /// Sorted list of packages in package_map
    pub package_names: Vec<String>,
    /// The ratchet values for all packages
    pub package_map: HashMap<String, Package>,
}

impl Nixpkgs {
    /// Validates the ratchet checks for Nixpkgs
    pub fn compare(from: Self, to: Self) -> Validation<()> {
        validation::sequence_(
            // We only loop over the current attributes,
            // we don't need to check ones that were removed
            to.package_names.into_iter().map(|name| {
                Package::compare(&name, from.package_map.get(&name), &to.package_map[&name])
            }),
        )
    }

    pub fn migrate(&self, nix_file_store: &mut NixFileStore) -> anyhow::Result<()> {
        for name in self.package_names.iter() {
            let pkg = &self.package_map[name];
            pkg.migrate(nix_file_store, &name)?
        }
        //nix_file_store.render()?;
        Ok(())
    }
}

/// The ratchet value for a top-level package
pub struct Package {
    /// The ratchet value for the check for non-auto-called empty arguments
    pub manual_definition: RatchetState<ManualDefinition>,

    /// The ratchet value for the check for new packages using pkgs/by-name
    pub uses_by_name: RatchetState<UsesByName>,
}

impl Package {
    /// Validates the ratchet checks for a top-level package
    pub fn compare(name: &str, optional_from: Option<&Self>, to: &Self) -> Validation<()> {
        validation::sequence_([
            RatchetState::<ManualDefinition>::compare(
                name,
                optional_from.map(|x| &x.manual_definition),
                &to.manual_definition,
            ),
            RatchetState::<UsesByName>::compare(
                name,
                optional_from.map(|x| &x.uses_by_name),
                &to.uses_by_name,
            ),
        ])
    }

    pub fn migrate(&self, nix_file_store: &mut NixFileStore, name: &str) -> anyhow::Result<()> {
        self.manual_definition.migrate(nix_file_store, name)?;
        self.uses_by_name.migrate(nix_file_store, name)?;
        Ok(())
    }
}

/// The ratchet state of a generic ratchet check.
pub enum RatchetState<Ratchet: ToNixpkgsProblem> {
    /// The ratchet is loose, it can be tightened more.
    /// In other words, this is the legacy state we're trying to move away from.
    /// Introducing new instances is not allowed but previous instances will continue to be allowed.
    /// The `Context` is context for error messages in case a new instance of this state is
    /// introduced
    Loose(Ratchet::ToContext),
    /// The ratchet is tight, it can't be tightened any further.
    /// This is either because we already use the latest state, or because the ratchet isn't
    /// relevant.
    Tight,
    /// This ratchet can't be applied.
    /// State transitions from/to NonApplicable are always allowed
    NonApplicable,
}

/// A trait that can convert an attribute-specific error context into a NixpkgsProblem
pub trait ToNixpkgsProblem {
    /// Context relating to the Nixpkgs that is being transitioned _to_
    type ToContext;

    /// How to convert an attribute-specific error context into a NixpkgsProblem
    fn to_nixpkgs_problem(
        name: &str,
        optional_from: Option<()>,
        to: &Self::ToContext,
    ) -> NixpkgsProblem;

    fn migrate(nix_file_store: &mut NixFileStore, context: &Self::ToContext, name: &str) -> anyhow::Result<()>;
}

impl<Context: ToNixpkgsProblem> RatchetState<Context> {
    /// Compare the previous ratchet state of an attribute to the new state.
    /// The previous state may be `None` in case the attribute is new.
    fn compare(name: &str, optional_from: Option<&Self>, to: &Self) -> Validation<()> {
        match (optional_from, to) {
            // Loosening a ratchet is now allowed
            (Some(RatchetState::Tight), RatchetState::Loose(loose_context)) => {
                Context::to_nixpkgs_problem(name, Some(()), loose_context).into()
            }

            // Introducing a loose ratchet is also not allowed
            (None, RatchetState::Loose(loose_context)) => {
                Context::to_nixpkgs_problem(name, None, loose_context).into()
            }

            // Everything else is allowed, including:
            // - Loose -> Loose (grandfathering policy for a loose ratchet)
            // - -> Tight (always okay to keep or make the ratchet tight)
            // - Anything involving NotApplicable, where we can't really make any good calls
            _ => Success(()),
        }
    }

    fn migrate(&self, nix_file_store: &mut NixFileStore, name: &str) -> anyhow::Result<()> {
        match self {
            RatchetState::Loose(context) => Context::migrate(nix_file_store, context, name),
            RatchetState::Tight => Ok(()),
            RatchetState::NonApplicable => Ok(()),
        }
    }
}

/// The ratchet to check whether a top-level attribute has/needs
/// a manual definition, e.g. in all-packages.nix.
///
/// This ratchet is only tight for attributes that:
/// - Are not defined in `pkgs/by-name`, and rely on a manual definition
/// - Are defined in `pkgs/by-name` without any manual definition,
///   (no custom argument overrides)
/// - Are defined with `pkgs/by-name` with a manual definition that can't be removed
///   because it provides custom argument overrides
///
/// In comparison, this ratchet is loose for attributes that:
/// - Are defined in `pkgs/by-name` with a manual definition
///   that doesn't have any custom argument overrides
pub enum ManualDefinition {}

impl ToNixpkgsProblem for ManualDefinition {
    type ToContext = ();

    fn to_nixpkgs_problem(
        name: &str,
        _optional_from: Option<()>,
        _to: &Self::ToContext,
    ) -> NixpkgsProblem {
        NixpkgsProblem::WrongCallPackage {
            relative_package_file: structure::relative_file_for_package(name),
            package_name: name.to_owned(),
        }
    }

    fn migrate(nix_file_store: &mut NixFileStore, context: &(), name: &str) -> anyhow::Result<()> {
        // This migrates only the empty call thing
        Ok(())
    }

    // We get a context, need to return either:
    // - How to automatically migrate
    // - How to manually migrate
}

/// The ratchet value of an attribute
/// for the check that new packages use pkgs/by-name
///
/// This checks that all new package defined using callPackage must be defined via pkgs/by-name
/// It also checks that once a package uses pkgs/by-name, it can't switch back to all-packages.nix
pub enum UsesByName {}

pub struct UsesByNameContext {
    pub call_package_argument_info: CallPackageArgumentInfo,
    pub file: PathBuf,
    pub line: usize,
    pub syntax_node: rnix::SyntaxNode,
}

impl ToNixpkgsProblem for UsesByName {
    type ToContext = UsesByNameContext;

    fn to_nixpkgs_problem(
        name: &str,
        optional_from: Option<()>,
        to: &Self::ToContext,
    ) -> NixpkgsProblem {
        if let Some(()) = optional_from {
            NixpkgsProblem::MovedOutOfByName {
                package_name: name.to_owned(),
                call_package_path: to.call_package_argument_info.relative_path.clone(),
                empty_arg: to.call_package_argument_info.empty_arg,
            }
        } else {
            NixpkgsProblem::NewPackageNotUsingByName {
                package_name: name.to_owned(),
                call_package_path: to.call_package_argument_info.relative_path.clone(),
                empty_arg: to.call_package_argument_info.empty_arg,
            }
        }
    }

    // What kind of actions are there?
    // - Move a path
    //   Update Nix files that reference that file
    // - Change a file
    //   When replacing Nix files:
    //   - remove an entry into an attribute set expression
    //
    //   Actions cannot overlap each other (technically they could, but it complicates stuff)

    fn migrate(nix_file_store: &mut NixFileStore, context: &Self::ToContext, name: &str) -> anyhow::Result<()> {
        let target = structure::relative_dir_for_package(&name);
        if let Some(relative_path) = &context.call_package_argument_info.relative_path {
            eprintln!("Would move {relative_path:?} to {target:?}");
            
            if context.call_package_argument_info.empty_arg {
                eprintln!("Replacing callPackage in {:?} line {:?}", context.file, context.line);

                let nix_file = nix_file_store.get(&context.file)?;

                // The nested indices to get to the entry to replace
                //let ancestor_indices : Vec<usize> = context.syntax_node.ancestors().map(|n| n.index()).collect();


                // We don't need to bother updating the syntax tree
                // We just need to remember the ranges we want to replace
                // Make sure they don't overlap
                // And then do the replacements

                //let c = context.syntax_node.clone_for_update();
                
                context.syntax_node.detach();
                //let attrs_node = context.syntax_node.parent().unwrap();
                //let index = context.syntax_node.index();

                //let new_green = attrs_node.green().remove_child(index);

                //let x = Token(GreenToken::new(rnix::NixLanguage::kind_to_raw(rnix::SyntaxKind::TOKEN_WHITESPACE), "THISISWHITESPACE"));
                //let new_green = green.replace_child(0, x);
                //let new_text = new_green.to_string();
                //eprintln!("New green node is: {new_text:?}");

                //nix_file.update_root_node(attrs_node.replace_with(new_green));

                //nix_file.render()?;
                //nix_file.syntax_root.
                //nix_file.syntax_root = context.syntax_node.replace_with()

                //panic!()

            } else {
                eprintln!("Would replace callPackage in {:?} line {:?} with `callPackage {target:?} ...`", context.file, context.line);
            }
            
            // This function needs to determine _whether_ we can migrate,
            // and the concrete steps to doing so
            // We should always be able to migrate, otherwise we wouldn't be here
            // This function should only fail if we can't migrate _automatically_

            // Can we migrate raw expressions?
            // We need to parse the source to figure out if it's actually a callPackage
            // That might be good to do even before actually..
            //if self.call_package_path.is_none() {
            //    eprintln!("No call package path for {name} at {location:?}");
            //}
        } else {
            eprintln!("Manual migration needed for {name}")
        }

        Ok(())
    }
}
