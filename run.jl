# Main script to run the biomass logistics model, compute results, and export to Excel.

using Gurobi
using CSV, DataFrames, JuMP, PrettyTables, Tables
import CSV, XLSX, Gurobi 

const AxisArray = Containers.DenseAxisArray

# helper functions for printing output tables
const DenseAxisArray = JuMP.Containers.DenseAxisArray
printtable(x::DenseAxisArray, tabletitle, unit) =
    pretty_table(x.data; column_labels=[unit], row_labels=x.axes[1], stubhead_label=tabletitle)
printtable(x::DenseAxisArray{Float64,2}, varname, unit) =
    pretty_table(x.data; column_labels=[x.axes[2], fill(unit, size(x,2))], row_labels=x.axes[1], stubhead_label=varname)



include("build_model.jl")
using .MyModel
include("utils.jl")

# --- Diagnostics & scenario runner -------------------------------------------------

using Statistics

function build_and_solve(;mip_gap=0.1, time_limit_s=60, modify_params_fn=nothing, scenname="base")
    sets = MyModel.load_sets()
    params = MyModel.load_params(sets)
    modify_params_fn !== nothing && modify_params_fn(params)
    model = Model(Gurobi.Optimizer)
    set_optimizer_attribute(model, "MIPGap", mip_gap)
    set_optimizer_attribute(model, "TimeLimit", time_limit_s)
    vars = MyModel.create_variables!(model, sets, params)
    constraints = MyModel.add_constraints!(model, sets, params, vars)
    MyModel.set_objective!(model, sets, params, vars)
    println("Solving scenario: $scenname (MIPGap=$mip_gap, TimeLimit=$time_limit_s s)")
    optimize!(model)
    obj = try objective_value(model) catch _; NaN end
    return (model, sets, params, vars, constraints, obj)
end

function compute_breakdown(sets, params, vars)
    # Extract containers
    vuse = vars.vuse; vimport = vars.vimport; vtransp = vars.vtransp; vinstalled = vars.vinstalled
    feed_cost = params.feed_cost; mode_prop = params.mode_prop

    # Feedstock cost and import
    feed_total = 0.0
    for n in sets.NODES, f in sets.TYPE, tech in sets.TECH, t in sets.T
        feed_total += value(vuse[n,f,tech,t]) * get(feed_cost,(n,f),0.0) / 1000
    end

    import_total = 0.0
    for n in sets.NODES, t in sets.T
        import_total +=  (value(vimport[n, :h2, t]) * get(feed_cost,(n, :h2),0.0) + value(vimport[n, :nh3, t]) * get(feed_cost,(n, :nh3),0.0))  / 1000
    end

    # Transport cost
    transport_truck = 0.0
    for n in sets.NODES, n2 in sets.NODES, f in sets.TYPE, m in sets.TRUCKS, t in sets.T
        transport_truck += value(vars.v_vehicles[n, n2, f, m, t]) * mode_prop[(m, :c_inv)] * params.annuity_mode[m]
                            + value(vars.v_vehicles[n, n2, f, m, t]) * (mode_prop[(m, :c_inv)] * mode_prop[(m, :c_om)]
                            + mode_prop[(m, :c_salary)] * mode_prop[(m, :num_driver)])
                            + value(vars.vtransp[n, n2, f, m, t]) * (1 / mode_prop[(m, :size)]) * params.dist[(n, n2)] *
                            mode_prop[(m, :winding)] * 2 * mode_prop[(m, :fuel_cons)] * mode_prop[(m, :c_fuel)] / 1_000_000
    end

    transp_ship = 0.0
    for n in sets.NODES, n2 in sets.NODES, f in sets.TYPE, m in sets.SHIPS, t in sets.T
        transp_ship += value(vars.v_vehicles[n,n2,f,m,t])*((mode_prop[(m, :c_inv)] + (1 / 30) * 4.98) * params.annuity_mode[m]
                    + mode_prop[(m, :c_salary)] * mode_prop[(m, :num_driver)])
                    + value(vars.v_vehicles[n, n2, f, m, t]) * (
                            (mode_prop[(m, :c_inv)] + (1 / 30) * 4.98) * mode_prop[(m, :c_om)]
                            + mode_prop[(m, :c_fuel)] * params.dist[(n, n2)] * mode_prop[(m, :winding)]
                                * mode_prop[(m, :size)] * 1.5 * (mode_prop[(m, :t_op)] / params.t_trip[(n, n2, m)])
                        )
    end

    # Approx investment + fix O&M (M€)
    invest_total = 0.0
    for n in sets.NODES, tech in sets.TECH, t in sets.T
        inv = (value(vinstalled[n,tech,t]) - get(params.exist_cap,(n,tech,t),0.0)) * get(params.tech_prop,(tech,:c_inv),0.0) * params.annuity_tech[tech]
        inv += value(vinstalled[n,tech,t]) * get(params.tech_prop,(tech,:c_om_fix),0.0)
        inv += sum(value(vuse[n,type,tech,t]) * get(params.tech_prop,(tech,:c_om_var),0.0) for type in sets.TYPE) / 1000
        invest_total += inv
    end

    # CO2 cost + storage cost
    co2_cost_total = 0.0
    for n in sets.NODES, t in sets.T
        term = value(vars.vco2_emitted[n,:co2_fossil,t])
        co2_cost_total += term * params.CO2_price[t] / 1000
    end

    storage_cost_total = sum(value(vars.vtransp[n, :storage, co2, m, t]) * params.CO2_storage_cost / 1000
                             for n in sets.NODES, co2 in sets.CO2, m in sets.MODES, t in sets.T)

    # Waste flows for diagnostics
    total_waste_use = sum(value(vars.vuse[n, :waste, tech, t]) for n in sets.NODES, tech in sets.TECH, t in sets.T)
    total_waste_import = sum(value(vars.vimport[n, :waste, t]) for n in sets.NODES, t in sets.T)

    # Electricity use in 2045
    el_use_2045 = sum(value(vars.vuse[n, el, tech, 3])/1000 for n in sets.NODES, el in sets.EL, tech in sets.TECH)

    return Dict(
        :feed => feed_total,
        :imp => import_total,
        :transport_truck => transport_truck,
        :transp_ship => transp_ship,
        :invest => invest_total,
        :co2 => co2_cost_total,
        :storage => storage_cost_total,
        :waste_use => total_waste_use,
        :waste_import => total_waste_import,
        :el_use_2045 => el_use_2045
    )
end

(m1, s1, p1, v1, c1, obj1) = build_and_solve(mip_gap=0.015, time_limit_s=1200, modify_params_fn=nothing, scenname="base")
    d1 = compute_breakdown(s1, p1, v1)
    println("BASE  obj = $(obj1), breakdown = $(d1)")


# print the sum of vuse for each type for each timestep
for t in [2, 3]
  println("Timestep $t:")
  for ty in s1.TYPE
    total_use = sum(value(v1.vuse[n, ty, tech, t])/1000 for n in s1.NODES, tech in s1.TECH)
    println("  $ty: total use, TWh/a = ", total_use)
  end
end

# Print the sum of vgen for each type for timestep 2 and 3
for t in [2, 3]
  println("Timestep $t generation:")
  for ty in s1.TYPE
    total_gen = sum(value(v1.vgen[n, ty, t])/1000 for n in s1.NODES)
    println("  $ty: total gen, TWh/a = ", total_gen)
  end
end


current_dir = @__DIR__
# Export results to Excel
function export_results(model, sets, params, vars)
    # Create DataFrames for the variables
    df_vinstalled = df_3d(vars.vinstalled, sets.NODES, sets.TECH, sets.T; 
                           nA=:node, nB=:tech, nC=:timestep, nV=:value, drop_zeros=true)
    df_vnewcap = df_3d(vars.vnewcap, sets.NODES, sets.TECH, sets.T; 
                        nA=:node, nB=:tech, nC=:timestep, nV=:value, drop_zeros=true)
    df_vtransp = df_5d(vars.vtransp, sets.NODES, sets.NODES, sets.TYPE, sets.MODES, sets.T; 
                        nA=:from_node, nB=:to_node, nC=:commodity, nD=:mode, nE=:timestep, nV=:value, drop_zeros=true)
    df_vuse = df_4d(vars.vuse, sets.NODES, sets.TYPE, sets.TECH, sets.T;
                     nA=:node, nB=:type, nC=:tech, nD=:timestep, nV=:value, drop_zeros=true)
    df_vgen = df_3d(vars.vgen, sets.NODES, sets.TYPE, sets.T;
                     nA=:node, nB=:type, nC=:timestep, nV=:value, drop_zeros=true)
    df_vco2_comb = df_3d(vars.vco2_comb, sets.NODES, sets.CO2, sets.T;
                          nA=:node, nB=:co2_type, nC=:timestep, nV=:value, drop_zeros=true)
    df_vco2_captured = df_3d(vars.vco2_captured, sets.NODES, sets.CO2, sets.T;
                              nA=:node, nB=:co2_type, nC=:timestep, nV=:value, drop_zeros=true)
    df_vco2_emitted = df_3d(vars.vco2_emitted, sets.NODES, sets.CO2, sets.T;
                             nA=:node, nB=:co2_type, nC=:timestep, nV=:value, drop_zeros=true)
    df_vimport = df_3d(vars.vimport, sets.NODES, sets.TYPE, sets.T;
                        nA=:node, nB=:type, nC=:timestep, nV=:value, drop_zeros=true)
    df_v_vehicles = df_5d(vars.v_vehicles, sets.NODES, sets.NODES, sets.TYPE, sets.VEHICLES, sets.T;
                           nA=:from_node, nB=:to_node, nC=:commodity, nD=:vehicle, nE=:timestep, nV=:value, drop_zeros=true)
    df_v_newvehicles = df_5d(vars.v_newvehicles, sets.NODES, sets.NODES, sets.TYPE, sets.VEHICLES, sets.T;
                              nA=:from_node, nB=:to_node, nC=:commodity, nD=:vehicle, nE=:timestep, nV=:value, drop_zeros=true)
    df_v_num_ships = df_5d(vars.v_num_ships, sets.NODES, sets.NODES, sets.TYPE, sets.SHIPS, sets.T;
                            nA=:from_node, nB=:to_node, nC=:commodity, nD=:ship, nE=:timestep, nV=:value, drop_zeros=true)
    
    # Create DataFrame for scalar vtotcost
    df_vtotcost = DataFrame(variable="vtotcost", value=value(vars.vtotcost))
    
    # Combine all dataframes into a list
    all_dfs = [df_vinstalled, df_vnewcap, df_vtransp, df_vuse, df_vgen, df_vco2_comb, 
               df_vco2_captured, df_vco2_emitted, df_vimport, df_v_vehicles, 
               df_v_newvehicles, df_v_num_ships, df_vtotcost]
    
    # Convert Symbol columns to strings (XLSX doesn't support Symbols)
    for df in all_dfs
        for col in names(df)
            if eltype(df[!, col]) == Symbol
                df[!, col] = string.(df[!, col])
            end
        end
    end
    
    # Export to Excel with multiple sheets (overwrite if exists)
    outpath = joinpath(current_dir, "results.xlsx")
    sheet_dict = Dict(
        "vinstalled" => df_vinstalled, "vnewcap" => df_vnewcap, "vtransp" => df_vtransp,
        "vuse" => df_vuse, "vgen" => df_vgen, "vco2_comb" => df_vco2_comb,
        "vco2_captured" => df_vco2_captured, "vco2_emitted" => df_vco2_emitted,
        "vimport" => df_vimport, "v_vehicles" => df_v_vehicles,
        "v_newvehicles" => df_v_newvehicles, "v_num_ships" => df_v_num_ships,
        "vtotcost" => df_vtotcost
    )
    XLSX.openxlsx(outpath, mode="w") do xf
        for (sheetname, df) in sheet_dict            
            XLSX.addsheet!(xf, sheetname)            
            XLSX.writetable!(xf[sheetname], df)
        end
    end
    println("Results exported to: $outpath")
end

export_results(m1, s1, p1, v1)