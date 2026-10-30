# GDAM action contract snapshots

`install.yml` and `publish.yml` are verbatim upstream action definitions from
`aviorstudio/gdam-actions` commit `d735444eb470194585def44521d5d91df2260e63`:

- https://github.com/aviorstudio/gdam-actions/blob/d735444eb470194585def44521d5d91df2260e63/install/action.yml
- https://github.com/aviorstudio/gdam-actions/blob/d735444eb470194585def44521d5d91df2260e63/publish/action.yml

These are data only, not executable local actions. Update both snapshots and the
checker's immutable revision together when upgrading the action. The publish
script at this revision accepts an exact release tag and optional asset; it does
not take a separately supplied version. The install action does accept version.
