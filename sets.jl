# This file defines the sets used in the model.

function load_sets()

    T = collect(1:3) # Vector Int

    TYPE = [
        :grot, :bark, :sawdust, :stem_wood, :waste, :rt, :h2,
        :el_won, :el_woff, :el_pvplant, :el_pvroof,
        :heat, :nh3, :co2_fossil, :co2_bio,
        :syngas, :meoh, :pyoil, :pyoil_upgrade
    ]

    FEEDSTOCK = Set([
        :grot, :bark, :sawdust, :stem_wood, :waste, :rt,
        :co2_fossil, :co2_bio, :h2, :nh3
    ])

    NON_CO2_EL = Set([
        :grot, :bark, :sawdust, :stem_wood, :waste, :rt, :meoh, :syngas, 
        :nh3, :heat, :h2, :pyoil, :pyoil_upgrade
    ])

    INTERMEDIATE = Set([
        :h2, :co2_fossil, :co2_bio, :syngas, :pyoil, :pyoil_upgrade
    ])

    HEAT_FUELS = Set([
        :grot, :bark, :sawdust, :stem_wood, :waste, :rt, 
        :el_won, :el_woff, :el_pvplant, :el_pvroof
    ])

    BIO_FUEL = Set([:grot, :bark, :sawdust, :stem_wood, :rt])
    FUEL     = Set([:grot, :bark, :sawdust, :stem_wood, :waste, :rt])

    CO2 = Set([:co2_fossil, :co2_bio])
    EL  = Set([:el_won, :el_woff,:el_pvplant, :el_pvroof])

    MODES = [:ship10, :truck_co2,
        :pipeline_on, :pipeline_off,
        :truck_bio, :ship_bio,
        :truck_meoh,:ship_meoh, 
        :pipeline_h2]

    VEHICLES = Set([:ship10, :truck_co2,
        :truck_bio, :ship_bio,
        :truck_meoh, :ship_meoh])
    SHIPS   = Set([:ship10, :ship_bio, :ship_meoh])
    TRUCKS  = Set([:truck_co2, :truck_bio, :truck_meoh])

    PIPELINE_CO2 = Set([:pipeline_on, :pipeline_off])
    CO2_VEH      = Set([:ship10, :truck_co2])
    BIO_VEH      = Set([:ship_bio, :truck_bio])
    MEOH_VEH     = Set([:ship_meoh, :truck_meoh])

    NODES = [:hub1, :hub2, :hub3, :hub4, :hub5, :hub6, :hub7, :hub8, :hub9, :hub10,
                          :hub11, :hub12, :hub13, :hub14, :hub15, :hub16, :hub17, :hub18, :hub19,
                          :hub20, :hub21, :hub22, :hub23, :hub24, :hub25, :hub26,
                          :storage]

    HUBS = Set([:hub1, :hub2, :hub3, :hub4, :hub5, :hub6, :hub7, :hub8, :hub9, :hub10,
                          :hub11, :hub12, :hub13, :hub14, :hub15, :hub16, :hub17, :hub18, :hub19,
                          :hub20, :hub21, :hub22, :hub23, :hub24, :hub25, :hub26])

    HARBORS = Set([
        :hub2, :hub4, :hub5, :hub9,:hub12,
        :hub14,:hub15,:hub16,
        :hub19, :hub20,
        :hub23, :hub24, :hub25, :hub26,
        :storage
    ])

    NONHARBORS = Set([
        :hub1, :hub3, :hub6, :hub7, :hub8, :hub10, :hub11, :hub13, :hub17, :hub18, :hub21, :hub22
    ])

    TECH =[
        :synthesis,
        :electrolysis_won, :electrolysis_woff, :electrolysis_pvplant, :electrolysis_pvroof,
        :gf,
        :hob_bio, :hob_waste, :chp_bio, :chp_waste,
        :eb, :hp,
        :ammonia_crack,
        :co2_capture,
        :won, :woff, :pvplant, :pvroof,
        :dac,
        :fast_pyr, :cat_pyr, :slow_pyr, :pyr_b
    ]

    BOILERS = Set([:hob_bio, :hob_waste, :chp_bio, :chp_waste])
    PYRA    = Set([:fast_pyr, :cat_pyr, :slow_pyr])
    PTH     = Set([:eb, :hp])
    ELGEN   = Set([:won, :woff, :pvplant, :pvroof])
    WIND    = Set([:won, :woff])
    PV      = Set([:pvplant, :pvroof])

    NON_RES = Set([
        :hob_bio, :hob_waste, :chp_bio, :chp_waste, :eb, :hp, :ammonia_crack, :co2_capture, :dac,
        :electrolysis_won, :electrolysis_woff, :electrolysis_pvplant, :electrolysis_pvroof,
        :synthesis, :gf,
        :fast_pyr, :cat_pyr, :slow_pyr, :pyr_b
    ])

    NON_BIO_FEED = Set([
        :won, :woff, :pvplant, :pvroof, :eb, :hp, :ammonia_crack, :co2_capture, :dac,
        :electrolysis_won, :electrolysis_woff, :electrolysis_pvplant, :electrolysis_pvroof, :synthesis
    ])

    ELECTROLYSIS = Set([
        :electrolysis_won, :electrolysis_woff, :electrolysis_pvplant, :electrolysis_pvroof
    ])

    TECH_PROP = [:c_inv, :c_om_var, :c_om_fix, :life, :flh, :em_factor, :n_el, :n_heat]

    NODE_PROP = [
        :lat, :long,
        :mw_bio, :mw_waste, :heat_demand,
        :mw_cflis, :mw_grot, :mw_bark, :mw_RT, :mw_sawdust
    ]

    MODE_PROP = [
        :c_inv, :c_om, :c_fuel, :c_salary, :c_harbor,
        :size, :t_op, :t_load, :t_unload, :life,
        :speed, :winding, :fuel_cons, :fuel_cons_still, :num_driver
    ]

    VRE_PROP = [:cap_won, :cap_woff, :cf_won, :cf_woff, 
            :cap_pvplant, :cap_pvroof, :cf_pvplant, :cf_pvroof]

    sets = (; T, TYPE, FEEDSTOCK, NON_CO2_EL, INTERMEDIATE, HEAT_FUELS,
        BIO_FUEL, FUEL, CO2, EL, MODES, VEHICLES, SHIPS, TRUCKS,
        PIPELINE_CO2, CO2_VEH, BIO_VEH, MEOH_VEH,
        NODES, HUBS, HARBORS, NONHARBORS,
        TECH, BOILERS, PYRA, PTH, ELGEN, WIND, PV,
        NON_RES, NON_BIO_FEED, ELECTROLYSIS,
        TECH_PROP, NODE_PROP, MODE_PROP, VRE_PROP)

    return sets

end