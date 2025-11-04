module GraphPPLGraphVizExt
using GraphPPL, MetaGraphsNext, GraphViz
import ReactiveMP: getaddons, AddonMemory, message_mapping_fform
import MetaGraphsNext: nv 

import GraphViz: load

"""
Abstract type defining node traversal strategies for graph visualization.

Concrete subtypes:
- `SimpleIteration`: Basic iteration through vertices
- `BFSTraversal`: Breadth-first search traversal from initial node

The choice of strategy affects both performance and visual layout.
"""
abstract type TraversalStrategy end

struct SimpleIteration <: TraversalStrategy end
struct BFSTraversal <: TraversalStrategy end


struct MsgInfo
    src  :: Int
    dst  :: Int
    resulting_message :: String
end


"""
return the `AddonMemory.memory.result` carried by `msg` or `nothing` if 
the message had no Memory addon.
"""
function _memory_result(msg)
    for addon in getaddons(msg)
        addon isa AddonMemory && return addon.memory.result
    end
    return nothing
end

default_formatter(x) = string(x)

"""
    DotOptions(font_size::Int, edge_len::Float64, layout::String,
               overlap::Bool, width::Float64, height::Float64)

A low‐level constructor for DOT‐generation options.

# Fields

- `font_size`:  `Int`  
   Font size (in points) for node labels.

- `edge_len`:   `Float64`  
   The `len` attribute for each edge (controls edge “spring” length).

- `layout`:     `String`  
   The GraphViz engine to use, e.g. `"dot"`, `"neato"`, `"fdp"`, etc.

- `overlap`:    `Bool`  
   Whether to emit `overlap=true` (`true`) or `overlap=false` (`false`).

- `width`:      `Float64`  
   Width of the drawing canvas, in inches.

- `height`:     `Float64`  
   Height of the drawing canvas, in inches.

"""

struct DotOptions
    font_size :: Int
    edge_len  :: Float64
    layout    :: String
    overlap   :: Bool
    width     :: Float64
    height    :: Float64
    edge_labelfontsize :: Int
    splines   :: Bool
    nodesep   :: Float64
    ranksep   :: Float64
    margin    :: Float64
end

"""
    DotOptions(; font_size::Int = 12,
                 edge_len::Float64 = 1.0,
                 layout::String = "neato",
                 overlap::Bool = false,
                 width::Float64 = 10.0,
                 height::Float64 = 10.0)

Construct a `DotOptions` instance with sensible defaults for:

- node font size,
- edge length,
- layout engine,
- overlap setting, and
- canvas dimensions.

Use this to bundle all GraphViz rendering options into one object.
"""

function DotOptions(; 
    font_size=11, edge_len=1.0, layout="fdp", overlap=false,
    width=12.0, height=12.0,                    # a bit bigger
    edge_labelfontsize=9, splines=true,
    nodesep=0.35, ranksep=0.45, margin=0.1
)
    DotOptions(font_size, edge_len, layout, overlap, width, height,
               edge_labelfontsize, splines, nodesep, ranksep, margin)
end

"""
    get_node_properties(model::GraphPPL.Model, vertex::Int64)

Extracts the properties of a specific node in a `GraphPPL.Model` and returns these as a dictionary.

# Arguments
- `model::GraphPPL.Model`: The model from which the node's properties will be retrieved.
- `vertex::Int64`: The integer index representing the node in the model's graph.

# Returns
- A `Dict{Symbol, Any}` where each key is a symbol corresponding to the node's property names 
(including the `label`), and the value is the corresponding property value.
"""
function get_node_properties(model::GraphPPL.Model, vertex::Int64)
    # Set up return value
    namespace_variables = Dict{Symbol, Any}()

    # Get the properties of the node   
    label = MetaGraphsNext.label_for(model.graph, vertex)
    properties = model[label].properties

    # Add label to the dictionary
    namespace_variables[:label] = label

    # Get field names
    field_names = fieldnames(typeof(properties))

    # Add field names and values to the dictionary
    for field_name in field_names

        # It might be wise to add GraphPPL.NodeData to this also. 
        namespace_variables[field_name] = getproperty(properties, field_name)
    end

    return namespace_variables
end

"""
    get_node_properties(properties::GraphPPL.FactorNodeProperties)

Extracts the properties of a factor node from a `GraphPPL.FactorNodeProperties` struct 
and returns them as a dictionary.

# Arguments
- `properties::GraphPPL.FactorNodeProperties`: A struct containing the factor node properties 
of a factor node in a probabilistic graphical model.

# Returns
- A `Dict{Symbol, Any}` where each key is the name of a field in the `properties` 
object (as a symbol), and the corresponding value is the value of that field.
"""
function get_node_properties(properties::GraphPPL.FactorNodeProperties)
    # Set up return value
    namespace_variables = Dict{Symbol, Any}()

    # Get field names
    field_names = fieldnames(typeof(properties))

    # Add field names and values to the dictionary
    for field_name in field_names
        namespace_variables[field_name] = getproperty(properties, field_name)
    end

    return namespace_variables
end

"""
    get_node_properties(properties::GraphPPL.VariableNodeProperties)

Extracts the properties of a variable node from a `GraphPPL.VariableNodeProperties` struct 
and returns these as a dictionary.

# Arguments
- `properties::GraphPPL.VariableNodeProperties`: A struct containing the variable node properties.

# Returns
- A `Dict{Symbol, Any}` where each key is the name of a field in the `properties` 
object (as a symbol), and the corresponding value is the value of that field.
"""
function get_node_properties(properties::GraphPPL.VariableNodeProperties)
    # Set up return value
    namespace_variables = Dict{Symbol, Any}()

    # Get field names
    field_names = fieldnames(typeof(properties))

    # Add field names and values to the dictionary
    for field_name in field_names
        namespace_variables[field_name] = getproperty(properties, field_name)
    end

    return namespace_variables
end

"""
    get_namespace_variables_dict(model::GraphPPL.Model)

Maps each node's global counter ID to its properties.

# Arguments
- `model::GraphPPL.Model`: The model to extract node properties from

# Returns
- `Dict{Int64, Dict{Symbol, Any}}`: Maps node IDs to property dictionaries
"""
function get_namespace_variables_dict(model::GraphPPL.Model)
    node_properties_dict = Dict{Int64, Dict{Symbol, Any}}()

    for vertex in MetaGraphsNext.vertices(model.graph)
        node_properties = get_node_properties(model, vertex)

        global_counter_id = node_properties[:label].global_counter

        node_properties_dict[global_counter_id] = node_properties
    end

    return node_properties_dict
end

"""
    get_sanitized_variable_node_name(var_namespace_dict::Dict{Symbol, Any})

Creates a sanitized string representation of a variable node in the format "label:value".

# Arguments
- `var_namespace_dict::Dict{Symbol, Any}`: Dictionary containing the variable node's properties

# Returns
- `String`: Node representation in format "label:value", where value is "nothing" if null
"""
function get_sanitized_variable_node_name(var_namespace_dict::Dict{Symbol, Any})
    san_str_name_var = string(var_namespace_dict[:label]) # was :name

    if isnothing(var_namespace_dict[:value])
        str_val_var = "nothing"
    else
        str_val_var = string(var_namespace_dict[:value])
    end

    final_str = string(san_str_name_var, ":", str_val_var)

    return final_str
end

"""
    get_sanitized_factor_node_name(fac_namespace_dict::Dict{Symbol, Any})

Converts a factor node's label to a sanitized string name.

# Arguments
- `fac_namespace_dict::Dict{Symbol, Any}`: Dictionary containing the factor node's properties

# Returns
- `String`: Sanitized string name derived from the node's label
"""
function get_sanitized_factor_node_name(fac_namespace_dict::Dict{Symbol, Any})
    san_str_name_fac = string(fac_namespace_dict[:label]) # was :fform
    san_str_name_fac = replace(san_str_name_fac, "\"" => "", "#" => "")
    return san_str_name_fac
end

"""
    get_sanitized_node_name(single_node_namespace_dict::Dict{Symbol, Any})

Returns a sanitized name string for either a variable or factor node.

# Arguments
- `single_node_namespace_dict`: Dictionary containing node properties

# Returns
- Sanitized name string for the node

Calls `get_sanitized_variable_node_name` if dict has `:name` key,
or `get_sanitized_factor_node_name` if dict has `:fform` key.
Throws error if neither key exists.
"""
function get_sanitized_node_name(single_node_namespace_dict::Dict{Symbol, Any})
    if haskey(single_node_namespace_dict, :name)
        san_node_name_str = get_sanitized_variable_node_name(single_node_namespace_dict)
    elseif haskey(single_node_namespace_dict, :fform)
        san_node_name_str = get_sanitized_factor_node_name(single_node_namespace_dict)
    else
        error("Input single-node namespace dictionary has neither :name nor :fform as a key.")
    end
    return san_node_name_str
end

"""
    get_displayed_label(properties::GraphPPL.FactorNodeProperties) :: String

Returns a quoted display label for a factor node.

# Arguments
- `properties`: Properties of the factor node

# Returns
- `String`: The factor node's pretty name enclosed in double quotes
"""
function get_displayed_label(properties::GraphPPL.FactorNodeProperties)
    # Ensure that the result of prettyname is enclosed in quotes
    label = GraphPPL.prettyname(properties)
    return "\"" * label * "\""
end

"""
    get_displayed_label(properties::GraphPPL.VariableNodeProperties) :: String

Returns a formatted label string for a variable node.

# Arguments
- `properties`: Properties of the variable node

# Returns
- `String`: Label formatted as:
  - Quoted value for constants (e.g. "5") 
  - HTML with subscript for indexed variables (e.g. x<sub>1</sub>)
  - Quoted name for regular variables (e.g. "x")
"""
function get_displayed_label(properties::GraphPPL.VariableNodeProperties)
    if GraphPPL.is_constant(properties)
        # Ensure constants are returned as strings enclosed in quotes
        return "\"" * string(GraphPPL.value(properties)) * "\""

    elseif !isnothing(GraphPPL.index(properties))
        # HTML format for labels with indices
        return string("<", GraphPPL.getname(properties), "<SUB><FONT POINT-SIZE=\"6\">", GraphPPL.index(properties), "</FONT></SUB>", ">")
    else
        # For non-HTML labels, ensure it's enclosed in quotes
        return "\"" * string(GraphPPL.getname(properties)) * "\""
    end
end

"""
Writes DOT notation for nodes in a graph using simple iteration.

Iterates through vertices and writes DOT format for:
- Factor nodes: Light gray squares
- Variable nodes: Circles

# Arguments
- `io_buffer::IOBuffer`: Buffer to write DOT output
- `model_graph::GraphPPL.Model`: Factor graph model to visualize
- `global_namespace_dict::Dict{Int64, Dict{Symbol, Any}}`: Maps vertex IDs to metadata
- `::SimpleIteration`: Specifies simple iteration strategy

# Raises
- `Error`: If a vertex has an unrecognized type
"""
function add_nodes!(
    io_buffer::IOBuffer, model_graph::GraphPPL.Model, global_namespace_dict::Dict{Int64, Dict{Symbol, Any}}, ::SimpleIteration
)
    for vertex in MetaGraphsNext.vertices(model_graph.graph)
        san_label = get_sanitized_node_name(global_namespace_dict[vertex])

        # index the label of model_namespace_variables with "vertex"
        label = MetaGraphsNext.label_for(model_graph.graph, vertex)

        properties = model_graph[label].properties
        displayed_label = get_displayed_label(properties)

        if isa(properties, GraphPPL.FactorNodeProperties)
            displayed_label = replace(displayed_label, "\"" => "", "#" => "")
            write(io_buffer, "    \"$(san_label)\" [shape=square, style=filled, fillcolor=lightgray, label=\"$(displayed_label)\"];\n")
        elseif isa(properties, GraphPPL.VariableNodeProperties)
            write(io_buffer, "    \"$(san_label)\" [shape=circle, label=$(displayed_label)];\n")
        else
            error("Unknown node type for label $(san_label)")
        end
    end
end

"""
Writes DOT syntax for nodes in a graph visualization using breadth-first search traversal.

Traverses the graph starting from the first created node and writes DOT notation for each node:
- Factor nodes are drawn as light gray squares
- Variable nodes are drawn as circles

# Arguments
- `io_buffer::IOBuffer`: Buffer to write the DOT string
- `model_graph::GraphPPL.Model`: Factor graph model to extract nodes from
- `global_namespace_dict::Dict{Int64, Dict{Symbol, Any}}`: Maps vertex IDs to namespace metadata
- `::BFSTraversal`: Specifies BFS traversal strategy

# Raises
- `Error`: If a node has an unrecognized type
"""
function add_nodes!(io_buffer::IOBuffer, model_graph::GraphPPL.Model, global_namespace_dict::Dict{Int64, Dict{Symbol, Any}}, ::BFSTraversal)
    n = nv(model_graph) # number of nodes in the model_graph
    visited = falses(n) # array of visited nodes
    cur_level = Vector{Int}() # current level of nodes processed in BFS/current layer of the BFS iteration
    next_level = Vector{Int}() # next level of nodes for BFS iteration

    s = 1 # always start at the initially created node of model_graph
    if !visited[s]
        visited[s] = true
        push!(cur_level, s)
    end

    while !isempty(cur_level)
        for v in cur_level # iterate over the verticies in the current level

            # we use the sanitized vertex label in the visualization
            san_label = get_sanitized_node_name(global_namespace_dict[v])

            label = MetaGraphsNext.label_for(model_graph.graph, v)
            properties = model_graph[label].properties
            displayed_label = get_displayed_label(properties)

            if isa(properties, GraphPPL.FactorNodeProperties)
                displayed_label = replace(displayed_label, "\"" => "", "#" => "")
                write(io_buffer, "    \"$(san_label)\" [shape=square, style=filled, fillcolor=lightgray, label=\"$(displayed_label)\"];\n")
            elseif isa(properties, GraphPPL.VariableNodeProperties)
                write(io_buffer, "    \"$(san_label)\" [shape=circle, label=$(displayed_label)];\n")
            else
                error("Unknown node type for label $(san_label)")
            end

            for v_neighb in MetaGraphsNext.neighbors(model_graph.graph, v)
                if !visited[v_neighb]
                    visited[v_neighb] = true
                    push!(next_level, v_neighb)
                end
            end
        end
        empty!(cur_level)
        cur_level, next_level = next_level, cur_level
        sort!(cur_level)
    end
end

# """
# Writes DOT syntax for edges in a graph visualization using simple iteration.

# # Arguments
# - `io_buffer::IOBuffer`: Buffer to write the DOT string
# - `model_graph::GraphPPL.Model`: Factor graph model to extract edges from 
# - `global_namespace_dict::Dict{Int64, Dict{Symbol, Any}}`: Node metadata dictionary
# - `::SimpleIteration`: Simple iteration strategy
# - `edge_length::Float64`: Visual length of edges in the graph

# Iterates through edges in the graph and writes DOT syntax for each one, with edge lengths
# controlled by `edge_length`. Uses node metadata from `global_namespace_dict` to generate
# node labels.
# """
# function add_edges!(
#     io_buffer::IOBuffer,
#     model_graph::GraphPPL.Model,
#     global_namespace_dict::Dict{Int64, Dict{Symbol, Any}},
#     ::SimpleIteration,
#     edge_length::Float64
# )
#     for edge in MetaGraphsNext.edges(model_graph.graph)
#         source_vertex = MetaGraphsNext.label_for(model_graph.graph, edge.src)
#         dest_vertex = MetaGraphsNext.label_for(model_graph.graph, edge.dst)

#         # we use the sanitized names of the vertices in the final visualization
#         source_san_name = get_sanitized_node_name(global_namespace_dict[source_vertex.global_counter])
#         dest_san_name = get_sanitized_node_name(global_namespace_dict[dest_vertex.global_counter])

#         write(io_buffer, "    \"$(source_san_name)\" -- \"$(dest_san_name)\" [len=$(edge_length)];\n")
#     end
# end

"""
Writes DOT syntax for edges in a graph visualization using simple iteration.

# Arguments
- `io_buffer::IOBuffer`: Buffer to write the DOT string
- `model_graph::GraphPPL.Model`: Factor graph model to extract edges from 
- `global_namespace_dict::Dict{Int64, Dict{Symbol, Any}}`: Node metadata dictionary
- `::SimpleIteration`: Simple iteration strategy
- `edge_length::Float64`: Visual length of edges in the graph

Iterates through edges in the graph and writes DOT syntax for each one, with edge lengths
controlled by `edge_length`. Uses node metadata from `global_namespace_dict` to generate
node labels.
"""
function add_edges!(
    io_buffer::IOBuffer,
    model_graph::GraphPPL.Model,
    global_namespace_dict::Dict{Int64, Dict{Symbol, Any}},
    ::SimpleIteration,
    edge_length::Float64,
    res_map::Dict{Tuple{Int,Int}, String} = Dict(),
    label_attr::Symbol = :xlabel
)
    for edge in MetaGraphsNext.edges(model_graph.graph)
        source_vertex = MetaGraphsNext.label_for(model_graph.graph, edge.src)
        dest_vertex = MetaGraphsNext.label_for(model_graph.graph, edge.dst)

        # we use the sanitized names of the vertices in the final visualization
        source_san_name = get_sanitized_node_name(global_namespace_dict[source_vertex.global_counter])
        dest_san_name = get_sanitized_node_name(global_namespace_dict[dest_vertex.global_counter])

        # write(io_buffer, "    \"$(source_san_name)\" -- \"$(dest_san_name)\" [len=$(edge_length)];\n")

        key = (min(edge.src, edge.dst), max(edge.src, edge.dst)) # permutation invariant edge tuple
        label = get(res_map, key, nothing)
        if isnothing(label)
            write(
                io_buffer,
                "    \"$(source_san_name)\" -- \"$(dest_san_name)\" [len=$(edge_length)];\n"
            )
        else
            attr = string(label_attr)
            write(
                io_buffer,
                "    \"$(source_san_name)\" -- \"$(dest_san_name)\" ",
                "[len=$(edge_length), $(attr)=\"", replace(label, "\""=>"\\\""), "\"];\n"
            )
        end
    end
end

# """
# Generates DOT syntax for edges in a graph visualization using breadth-first search traversal.

# # Arguments
# - `io_buffer::IOBuffer`: Buffer to write the DOT string
# - `model_graph::GraphPPL.Model`: Factor graph model to extract edges from
# - `global_namespace_dict::Dict{Int64, Dict{Symbol, Any}}`: Node metadata dictionary
# - `::BFSTraversal`: BFS traversal strategy
# - `edge_length::Float64`: Visual length of edges in the graph

# Traverses the graph in BFS order and writes DOT syntax for each edge, with edge lengths 
# controlled by `edge_length`. Uses node metadata from `global_namespace_dict` to generate 
# node labels.
# """
# function add_edges!(
#     io_buffer::IOBuffer,
#     model_graph::GraphPPL.Model,
#     global_namespace_dict::Dict{Int64, Dict{Symbol, Any}},
#     ::BFSTraversal,
#     edge_length::Float64
# )
#     edge_set = Set{Tuple{Int, Int}}()

#     n = nv(model_graph)
#     visited = falses(n)
#     cur_level = Vector{Int}()
#     next_level = Vector{Int}()

#     s = 1
#     if !visited[s]
#         visited[s] = true
#         push!(cur_level, s)
#     end

#     while !isempty(cur_level)
#         for v in cur_level
#             for v_neighb in MetaGraphsNext.neighbors(model_graph.graph, v)
#                 edge = (min(v, v_neighb), max(v, v_neighb))
#                 if !(edge in edge_set)
#                     source_vertex = MetaGraphsNext.label_for(model_graph.graph, v)
#                     dest_vertex = MetaGraphsNext.label_for(model_graph.graph, v_neighb)

#                     source_san_name = get_sanitized_node_name(global_namespace_dict[source_vertex.global_counter])

#                     dest_san_name = get_sanitized_node_name(global_namespace_dict[dest_vertex.global_counter])

#                     write(io_buffer, "    \"$(source_san_name)\" -- \"$(dest_san_name)\" [len=$(edge_length)];\n")
#                     push!(edge_set, edge)
#                 end

#                 if !visited[v_neighb]
#                     visited[v_neighb] = true
#                     push!(next_level, v_neighb)
#                 end
#             end
#         end
#         empty!(cur_level)
#         cur_level, next_level = next_level, cur_level
#         sort!(cur_level)
#     end
# end


"""
Generates DOT syntax for edges in a graph visualization using breadth-first search traversal.

# Arguments
- `io_buffer::IOBuffer`: Buffer to write the DOT string
- `model_graph::GraphPPL.Model`: Factor graph model to extract edges from
- `global_namespace_dict::Dict{Int64, Dict{Symbol, Any}}`: Node metadata dictionary
- `::BFSTraversal`: BFS traversal strategy
- `edge_length::Float64`: Visual length of edges in the graph

Traverses the graph in BFS order and writes DOT syntax for each edge, with edge lengths 
controlled by `edge_length`. Uses node metadata from `global_namespace_dict` to generate 
node labels.
"""
function add_edges!(
    io_buffer::IOBuffer,
    model_graph::GraphPPL.Model,
    global_namespace_dict::Dict{Int64, Dict{Symbol, Any}},
    ::BFSTraversal,
    edge_length::Float64,
    res_map::Dict{Tuple{Int,Int}, String} = Dict(),
    label_attr::Symbol = :xlabel
)
    edge_set = Set{Tuple{Int, Int}}()

    n = nv(model_graph)
    visited = falses(n)
    cur_level = Vector{Int}()
    next_level = Vector{Int}()

    s = 1
    if !visited[s]
        visited[s] = true
        push!(cur_level, s)
    end

    while !isempty(cur_level)
        for v in cur_level
            for v_neighb in MetaGraphsNext.neighbors(model_graph.graph, v)
                edge = (min(v, v_neighb), max(v, v_neighb))
                if !(edge in edge_set)
                    source_vertex = MetaGraphsNext.label_for(model_graph.graph, v)
                    dest_vertex = MetaGraphsNext.label_for(model_graph.graph, v_neighb)

                    source_san_name = get_sanitized_node_name(global_namespace_dict[source_vertex.global_counter])

                    dest_san_name = get_sanitized_node_name(global_namespace_dict[dest_vertex.global_counter])

                    # write(io_buffer, "    \"$(source_san_name)\" -- \"$(dest_san_name)\" [len=$(edge_length)];\n")
                    # key = (min(edge.src, edge.dst), max(edge.src, edge.dst)) # permutation invariant edge tuple
                    # label = get(res_map, key, nothing)
                    label = get(res_map, edge, nothing)
                    if isnothing(label)
                        write(
                            io_buffer,
                            "    \"$(source_san_name)\" -- \"$(dest_san_name)\" [len=$(edge_length)];\n"
                        )
                    else
                        attr = string(label_attr)
                        write(
                            io_buffer,
                            "    \"$(source_san_name)\" -- \"$(dest_san_name)\" ",
                            "[len=$(edge_length), $(attr)=\"", replace(label, "\""=>"\\\""), "\"];\n"
                        )
                    end

                    push!(edge_set, edge)
                end

                if !visited[v_neighb]
                    visited[v_neighb] = true
                    push!(next_level, v_neighb)
                end
            end
        end
        empty!(cur_level)
        cur_level, next_level = next_level, cur_level
        sort!(cur_level)
    end
end

"""
A 'wrapper' arround a user-specified Symbolic expression which returns 
the associated traversal type. 
"""
function convert_strategy(strategy::Symbol)
    if strategy == :simple
        return SimpleIteration()
    elseif strategy == :bfs
        return BFSTraversal()
    else
        error("Unknown traversal strategy: $strategy")
    end
end

"""
    GraphVizGraphWrapper

A wrapper type for GraphViz.Graph that restricts display capabilities to SVG and text formats only.

This wrapper is designed to prevent display issues that can occur with PNG format on some systems
by limiting the available display formats to SVG and plain text.

# Fields
- `graph::GraphViz.Graph`: The wrapped GraphViz graph object
- `dot_string::String`: The DOT string representation of the graph
"""
struct GraphVizGraphWrapper
    graph::GraphViz.Graph
    dot_string::String
end

# Override showable to only allow SVG and text display
function Base.showable(mime::MIME, x::GraphVizGraphWrapper)
    if mime isa MIME"image/svg+xml" || mime isa MIME"text/plain"
        return showable(mime, x.graph)
    end
    return false
end

# Delegate show methods to the wrapped graph
function Base.show(io::IO, mime::MIME"image/svg+xml", x::GraphVizGraphWrapper)
    show(io, mime, x.graph)
end

function Base.show(io::IO, mime::MIME"text/plain", x::GraphVizGraphWrapper)
    show(io, mime, x.dot_string)
end


"""
    DotBuilder(io::IO, opts::DotOptions, traversal::TraversalStrategy)

A helper for incrementally constructing a GraphViz DOT representation of a
`GraphPPL.Model`. It bundles:

1.  `io_buffer` – an `IO` buffer into which the DOT text is written,
2.  `opts`      – a `DotOptions` struct holding all GraphViz parameters
                  (font size, edge length, layout engine, overlap, canvas size),
3.  `traversal` – a `TraversalStrategy` governing node/edge ordering
                  (`SimpleIteration()` or `BFSTraversal()`).

Once you create a `DotBuilder`, you invoke it on your model:

```julia
buf     = IOBuffer()
opts    = DotOptions()                  # use defaults
strat   = SimpleIteration()             # or BFSTraversal()
builder = DotBuilder(buf, opts, strat)

builder(my_model)                       # emits the DOT text into `buf`
dot_src = String(take!(buf))            # retrieve the DOT source
graph   = GraphViz.Graph(dot_src)       # parse & layout
```
"""
struct DotBuilder
    io_buffer  :: IO
    opts       :: DotOptions
    traversal  :: TraversalStrategy
    res_map    :: Dict{Tuple{Int, Int}, String}
    label_attr :: Symbol
end


"""
    (builder::DotBuilder)(model::GraphPPL.Model) -> IO

Generate the DOT description of `model` using the options in `builder.opts`
and the traversal strategy in `builder.traversal`, writing it into `builder.io_buffer`.
"""
function (builder::DotBuilder)(model::GraphPPL.Model)

    strat = builder.traversal

    ns_dict = get_namespace_variables_dict(model)
    io      = builder.io_buffer
    opt     = builder.opts

    # write(io, "graph G {\n")
    # write(io, "    layout=$(opt.layout);\n")
    # write(io, "    overlap=$(string(opt.overlap));\n")
    # write(io, "    size=\"$(opt.width),$(opt.height)!\";\n")
    # write(io, "    node [shape=circle, fontsize=$(opt.font_size)];\n")

    write(io, "graph G {\n")
    write(io, "    layout=$(opt.layout);\n")
    write(io, "    overlap=$(string(opt.overlap));\n")
    # drop the '!' so Graphviz can enlarge if needed
    write(io, "    size=\"$(opt.width),$(opt.height)\";\n")
    write(io, "    margin=$(opt.margin);\n")
    write(io, "    nodesep=$(opt.nodesep);\n")
    write(io, "    ranksep=$(opt.ranksep);\n")
    write(io, "    node [shape=circle, fontsize=$(opt.font_size)];\n")
    write(io, "    edge [labelfontsize=$(opt.edge_labelfontsize)];\n")
    write(io, "    splines=$(opt.splines ? "true" : "false");\n")



    add_nodes!(io, model, ns_dict, strat)
    # add_edges!(io, model, ns_dict, strat, opt.edge_len)
    add_edges!(
        io, model, ns_dict, strat, opt.edge_len, builder.res_map, builder.label_attr
    )

    write(io, "}\n")

    return builder.io_buffer
end


"""
    make_dot(model; traversal = SimpleIteration(), opts = DotOptions())

Return **only** the DOT source string for `model`.
"""
function make_dot(
    model::GraphPPL.Model; 
    traversal::TraversalStrategy,
    opts::DotOptions = DotOptions(),
    res_map::Dict{Tuple{Int, Int}, String} = Dict(),
    label_attr::Symbol = :xlabel
)
    io = IOBuffer()
    # DotBuilder(io, opts, traversal)(model)
    DotBuilder(io, opts, traversal, res_map, label_attr)(model)
    return String(take!(io))
end

"""
    make_graph(dot::AbstractString)

Convert a DOT string to `GraphViz.Graph`.
"""
make_graph(dot::AbstractString) = GraphViz.Graph(dot)

"""
    save(svg_graph, path::AbstractString)

Write the graph as SVG.  Any parent directories must exist.
"""
function save(graph::GraphViz.Graph, path::AbstractString)
    open(path, "w") do io
        show(io, MIME("image/svg+xml"), graph)
    end
    return path
end

# Return the human/base name of a (possibly parametric) type
_type_basename(T) = String(Base.typename(T).name)

"""
    GraphViz.load(model; [kwargs])

Back-compat wrapper that re-uses the small helpers above.
"""
function GraphViz.load(
    model::GraphPPL.Model;
    strategy::Symbol            = :simple,
    inference_result            = nothing,
    show_memory::Bool           = false,
    formatter::Function         = default_formatter,
    label_attr::Symbol          = :xlabel,
    font_size::Int              = 12,
    edge_length::Float64        = 2.0,
    layout::String              = "neato",
    overlap::Bool               = false,
    width::Float64              = 10.0,
    height::Float64             = 10.0,
    save_to::Union{String,Nothing} = nothing
)
    traversal_strategy = convert_strategy(strategy)

    # pre-compute memory-addon strings keyed by (src, dst):
    res_map = Dict{Tuple{Int,Int},String}()

    if show_memory && inference_result !== nothing

        # 1) Collect memory messages into buckets keyed by (var_sym, factor)
        buckets = Dict{Tuple{Symbol,String}, Vector{String}}()

        # helper: return Vector{AddonMemoryMessageMapping}-like objects for a posterior
        function _mem_mappings(x)
            out = Vector{Any}()
            for addon in getaddons(x)
                if addon isa AddonMemory
                    mem = addon.memory
                    if hasfield(typeof(mem), :mappings) # AddonMemoryProd
                        append!(out, mem.mappings)
                    else                                # Single mapping
                        push!(out, mem)
                    end
                end
            end
            return out
        end

        # Turn one memory mapping into a human label string.
        # Example: "Bernoulli:p -> θ : Beta(2.0, 1.0)"
        function _label_for(mm, var_sym; formatter::Function)
            F = message_mapping_fform(mm.mapping) # factor kind
            # fname = F isa DataType ? String(nameof(F)) : String(nameof(typeof(F))) # OG VERSION
            fname = _type_basename(F)
            # vtag is Val{:p}() / Val{:out}() etc. show as :p or :out
            vtag = mm.mapping.vtag
            port = vtag isa Val ? string(vtag) : string(vtag)

            # clean Val{:p}() -> p
            port = replace(replace(port, "Val{:" => ""), ("}()" => ""))

            msg_str = formatter(mm.result)
            return string(fname, ":", port, " -> ", String(var_sym), " : ", msg_str)
        end

        # Collect all outgoing factor -> variable messages per variable symbol and factor
        for (var_sym, post) in inference_result.posteriors
            for mm in _mem_mappings(post)
                # factor kind name (pretty, not the node id)
                F = message_mapping_fform(mm.mapping)
                # factor_name = F isa DataType ? String(nameof(F)) : String(nameof(typeof(F))) # OG VERSION
                factor_name = _type_basename(F)
                key = (var_sym, factor_name)
                push!(get!(buckets, key, String[]), _label_for(mm, var_sym; formatter))

                println("BUCKET + ", key)

            end
        end

        # 2) Walk model edges; bin (factor–variable) edges by (var_sym, factor)
        # First, helpers to inspect node properties
        _props(v) = begin
            lab = MetaGraphsNext.label_for(model.graph, v)
            model[lab].properties
        end
        _is_factor(v)   = _props(v) isa GraphPPL.FactorNodeProperties
        _is_variable(v) = _props(v) isa GraphPPL.VariableNodeProperties

        # variable vertex -> Symbol (e.g. :θ, :y)
        function _var_symbol(v)
            props = _props(v)::GraphPPL.VariableNodeProperties
            Symbol(GraphPPL.getname(props))
        end

        # factor vertex -> pretty name ("Bernoulli", "Beta", ...)
        function _factor_name(v)
            props = _props(v)::GraphPPL.FactorNodeProperties
            GraphPPL.prettyname(props)
        end

        # (var_sym, factor_name) -> sorted Vector{(min_id,max_id)} for undirected edge keying
        edge_bins = Dict{Tuple{Symbol,String}, Vector{Tuple{Int,Int}}}()

        for e in MetaGraphsNext.edges(model.graph)
            s, d = Int(e.src), Int(e.dst)

            if _is_factor(s) && _is_variable(d)
                key = (_var_symbol(d), _factor_name(s))
                push!(get!(edge_bins, key, Vector{Tuple{Int,Int}}()), (min(s,d), max(s,d)))

                # println("EDGEBIN + ", key)

            elseif _is_factor(d) && _is_variable(s)
                key = (_var_symbol(s), _factor_name(d))
                push!(get!(edge_bins, key, Vector{Tuple{Int,Int}}()), (min(s,d), max(s,d)))

                # println("EDGEBIN + ", key)

            else
                # ignore var–var or factor–factor (shouldn't occur anyway)
            end
        end

        foreach(v -> sort!(v), values(edge_bins))  # deterministic

        # 3) Assign labels: pair buckets to edges in order, fill res_map
        for (key, edges_vec) in edge_bins
            msgs = get(buckets, key, String[])
            isempty(msgs) && continue
            for (i, ed) in enumerate(edges_vec)
                i > length(msgs) && break
                res_map[ed] = msgs[i] # ed is (min_id, max_id), matches add_edges! key

                println("RESMAP  + ", ed, "  <=  ", msgs[i])
            end
        end

        # @debug "buckets keys" keys(buckets)
        # @debug "edge_bins keys" keys(edge_bins)
        # @info  "bucket size per key" Dict(k => length(v) for (k,v) in buckets)
        # @info  "edges per key"       Dict(k => length(v) for (k,v) in edge_bins)
        # @info  "res_map size"        length(res_map)

    end


    # dot_opts  = DotOptions(font_size, edge_length, layout, overlap, width, height)

    # hard-coded options since amending the fields of the `DotOptions` struuct:
    edge_font_size = 2
    nodesep=0.35
    ranksep=0.45
    margin=0.1

    dot_opts  = DotOptions(
        font_size, edge_length, layout, overlap, width, height, edge_font_size, true, nodesep, ranksep, margin
    )

    # dot = make_dot(model; traversal = traversal_strategy, opts = dot_opts)
    dot = make_dot(
        model; 
        traversal = traversal_strategy, 
        opts = dot_opts,
        res_map = res_map,
        label_attr = label_attr
    )

    graph = make_graph(dot)

    if save_to !== nothing
        save(graph, save_to)
    end

    return GraphVizGraphWrapper(graph, dot)
end

end



# # OG VERSION
# """
#     GraphViz.load(model; [kwargs])

# Back-compat wrapper that re-uses the small helpers above.
# """
# function GraphViz.load(
#     model::GraphPPL.Model;
#     strategy::Symbol            = :simple,
#     inference_result            = nothing,
#     show_memory::Bool           = false,
#     formatter::Function         = default_formatter,
#     label_attr::Symbol          = :xlabel,
#     font_size::Int              = 12,
#     edge_length::Float64        = 1.0,
#     layout::String              = "neato",
#     overlap::Bool               = false,
#     width::Float64              = 10.0,
#     height::Float64             = 10.0,
#     save_to::Union{String,Nothing} = nothing
# )
#     traversal_strategy = convert_strategy(strategy)

#     # pre-compute memory-addon strings keyed by (src, dst):
#     res_map = Dict{Tuple{Int,Int},String}()
#     if show_memory && inference_result !== nothing
#         # pass
#     end

#     dot_opts  = DotOptions(font_size, edge_length, layout, overlap, width, height)

#     # dot = make_dot(model; traversal = traversal_strategy, opts = dot_opts)
#     dot = make_dot(
#         model; 
#         traversal = traversal_strategy, 
#         opts = dot_opts,
#         res_map = res_map,
#         label_attr = label_attr
#     )

#     graph = make_graph(dot)

#     if save_to !== nothing
#         save(graph, save_to)
#     end

#     return GraphVizGraphWrapper(graph, dot)
# end