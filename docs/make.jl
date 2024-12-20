using Documenter, GraphPPL

DocMeta.setdocmeta!(GraphPPL, :DocTestSetup, :(using GraphPPL); recursive = true)

makedocs(
    modules  = [GraphPPL],
    clean    = true,
    sitename = "GraphPPL.jl",
    pages    = ["Home" => "index.md", "Getting Started" => "getting_started.md", "Syntax Guide" => "syntax_guide.md", "Nested Models" => "nested_models.md", "Plugins" => ["Overview" => "plugins/overview.md", "Variational Inference & Constraints" => "plugins/constraint_specification.md", "Attaching metadata to nodes" => "plugins/meta_specification.md", "Tracking creation of nodes" => "plugins/created_by.md", "Setting tag of nodes" => "plugins/node_tag.md", "Setting ID of nodes" => "plugins/node_id.md"], "Migration Guide (from v3 to v4)" => "migration_3_to_4.md", "Developers Guide" => "developers_guide.md", "Custom backend" => "custom_backend.md"],
    format   = Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true"),
    warnonly = false
)

if get(ENV, "CI", nothing) == "true"
    deploydocs(repo = "github.com/ReactiveBayes/GraphPPL.jl.git", devbranch = "main", forcepush = true)
end
