using JuMP
import Gurobi

module MyModel
mip_gap = 0.05

# ---------- Load components ----------
include("utils.jl")
include("sets.jl")
include("parameters.jl")
include("variables.jl")
include("constraints.jl")

function build(; optimizer, mip_gap::Union{Nothing,Float64}=0.05, time_limit_s::Union{Nothing,Int}=nothing)
    model = Model(optimizer)
    if mip_gap !== nothing
        set_optimizer_attribute(model, "MIPGap", mip_gap)
    end

    # 1) sets
    sets = load_sets()

    # 2) params (kan bero på sets)
    params = load_params(sets)

    # 3) variables (skapar JuMP-variabler)
    vars = create_variables!(model, sets, params)

    # 4) constraints (inkl. bounds/fixering och alla constraints)
    constraints = add_constraints!(model, sets, params, vars)

    # 5) objective
    set_objective!(model, sets, params, vars)

    return model, sets, params, vars, constraints
end

end # module