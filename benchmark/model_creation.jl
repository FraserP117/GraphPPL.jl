using BenchmarkTools
using GraphPPL

function benchmark_model_creation()
    SUITE = BenchmarkGroup()

    SUITE["model creation"]["state space (length)"] = benchmark_state_space_model()
    SUITE["model creation"]["hierarchical (depth)"] = benchmark_hierarchical_model()

    return SUITE
end

## State space model benchmarks

function benchmark_state_space_model()
    SUITE = BenchmarkGroup()

    for n in 10 .^ range(1, stop = 5)
        # This SUITE benchmarks how long it takes to create a state space model with length `n` and default constraints
        SUITE["default constraints", n] = @benchmarkable create_state_space_model($n)
        # This SUITE benchmarks how long it takes to create a state space model with length `n` and mean field constraints
        SUITE["mean field constraints", n] = @benchmarkable create_state_space_model($n, constraints) setup = begin
            constraints = state_space_mean_field_constraints()
        end
    end

    return SUITE
end

@model function state_space_model(n)
    μ ~ Normal(0, 1)
    σ ~ Gamma(1, 1)
    x[1] ~ Normal(μ, σ)
    for i in 2:n
        x[i] ~ Normal(x[i - 1], σ)
    end
end

state_space_mean_field_constraints() = @constraints begin
    q(x) = q(x[begin]) .. q(x[end])
    q(x, σ) = q(x)q(σ)
    q(μ, σ) = q(μ)q(σ)
end

function create_state_space_model(n::Int, constraints = nothing)
    plugins = if isnothing(constraints)
        GraphPPL.PluginsCollection()
    else
        GraphPPL.PluginsCollection(GraphPPL.VariationalConstraintsPlugin(constraints))
    end
    return GraphPPL.create_model(GraphPPL.with_plugins(state_space_model(n = n), plugins))
end

## Hierarchical model benchmarks

function benchmark_hierarchical_model()
    SUITE = BenchmarkGroup()

    for depth in 10 .^ range(1, stop = 2)
        # This SUITE benchmarks how long it takes to create a state space model with depth `n` and default constraints
        SUITE["default constraints", depth] = @benchmarkable create_hierarchical_model($depth)
        # This SUITE benchmarks how long it takes to create a state space model with depth `n` and mean field constraints
        SUITE["mean field constraints", depth] = @benchmarkable create_hierarchical_model($depth, constraints) setup = begin
            constraints = hierarchical_mean_field_constraints()
        end
    end

    return SUITE
end

@model function gcv(κ, ω, θ, x, y)
    log_σ := κ * ω + θ
    σ := exp(log_σ)
    y ~ Normal(x, σ)
end

@model function hgf(κ, ω, θ, x_begin, depth)
    means[1] ~ gcv(κ = κ, ω = ω, θ = θ, x = x_begin)
    for i in 2:depth
        means[i] ~ gcv(κ = κ, ω = ω, θ = θ, x = means[i - 1])
    end
end

hierarchical_mean_field_constraints() = @constraints begin
    q(means) = q(means[begin]) .. q(means[end])
    for q in gcv
        q(σ, log_σ) = q(σ)q(log_σ)
        q(x, σ, y) = q(x, y)q(σ)
    end
end

function create_hierarchical_model(depth::Int, constraints = nothing)
    plugins = if isnothing(constraints)
        GraphPPL.PluginsCollection()
    else
        GraphPPL.PluginsCollection(GraphPPL.VariationalConstraintsPlugin(constraints))
    end
    return GraphPPL.create_model(GraphPPL.with_plugins(hgf(depth = depth), plugins)) do model, ctx
        κ = GraphPPL.getorcreate!(model, ctx, :κ, nothing)
        ω = GraphPPL.getorcreate!(model, ctx, :ω, nothing)
        θ = GraphPPL.getorcreate!(model, ctx, :θ, nothing)
        x_begin = GraphPPL.getorcreate!(model, ctx, :x_begin, nothing)
        return (; κ = κ, ω = ω, θ = θ, x_begin = x_begin)
    end
end
