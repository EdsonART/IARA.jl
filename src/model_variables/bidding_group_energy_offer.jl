#  Copyright (c) 2024: PSR, CCEE (Câmara de Comercialização de Energia  
#      Elétrica), and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.
#############################################################################
# IARA
# See https://github.com/psrenergy/IARA.jl
#############################################################################

function bidding_group_energy_offer! end

function bidding_group_energy_offer!(
    model::SubproblemModel,
    inputs::Inputs,
    run_time_options::RunTimeOptions,
    ::Type{SubproblemBuild},
)
    buses = index_of_elements(inputs, Bus)
    bidding_groups = index_of_elements(inputs, BiddingGroup; run_time_options)
    bid_segments = bidding_segments(inputs)
    blks = blocks(inputs)

    # Variables
    @variable(
        model.jump_model,
        bidding_group_energy_offer[
            blk in blks,
            bg in bidding_groups,
            bds in 1:maximum_bid_segments(inputs, bg),
            bus in buses,
        ],
    )

    if run_mode(inputs) == Configurations_RunMode.STRATEGIC_BID
        return nothing
    end

    # Time series
    spot_price_series = time_series_spot_price(inputs)

    # Objective function
    @expression(
        model.jump_model,
        bidding_group_revenue[
            blk in blks,
            bg in bidding_groups,
            bds in 1:maximum_bid_segments(inputs, bg),
            bus in buses,
        ],
        -bidding_group_energy_offer[blk, bg, bds, bus] * spot_price_series[bus, blk],
    )

    model.obj_exp += sum(bidding_group_revenue; init = 0) * money_to_thousand_money()

    return nothing
end

function bidding_group_energy_offer!(
    model::SubproblemModel,
    inputs::Inputs,
    run_time_options::RunTimeOptions,
    scenario::Int,
    subscenario::Int,
    ::Type{SubproblemUpdate},
)
    bidding_groups = index_of_elements(inputs, BiddingGroup; run_time_options)
    buses = index_of_elements(inputs, Bus)
    bid_segments = bidding_segments(inputs)
    blks = blocks(inputs)

    if run_mode(inputs) == Configurations_RunMode.STRATEGIC_BID
        return nothing
    end

    # Variables
    bidding_group_energy_offer = get_model_object(model, :bidding_group_energy_offer)

    # Time series
    spot_price_series = time_series_spot_price(inputs)

    for blk in blks, bg in bidding_groups, bds in 1:maximum_bid_segments(inputs, bg), bus in buses
        set_objective_coefficient(
            model.jump_model,
            bidding_group_energy_offer[blk, bg, bds, bus],
            -spot_price_series[bus, blk] * money_to_thousand_money(),
        )
    end
    return nothing
end

function bidding_group_energy_offer!(
    outputs::Outputs,
    inputs::Inputs,
    run_time_options::RunTimeOptions,
    ::Type{InitializeOutput},
)
    add_symbol_to_query_from_subproblem_result!(
        outputs,
        :bidding_group_energy_offer,
    )

    labels = labels_for_output_by_pair_of_agents(
        inputs,
        run_time_options,
        inputs.collections.bidding_group,
        inputs.collections.bus;
        index_getter = all_buses,
    )

    initialize!(
        QuiverOutput,
        outputs;
        inputs,
        output_name = "bidding_group_energy_offer",
        dimensions = ["stage", "scenario", "block", "bid_segment"],
        unit = "GWh",
        labels,
        run_time_options,
    )
    return nothing
end

function bidding_group_energy_offer!(
    outputs::Outputs,
    inputs::Inputs,
    run_time_options::RunTimeOptions,
    simulation_results::SimulationResultsFromStageScenario,
    stage::Int,
    scenario::Int,
    subscenario::Int,
    ::Type{WriteOutput},
)
    write_bid_output(
        outputs,
        inputs,
        run_time_options,
        "bidding_group_energy_offer",
        simulation_results.data[:bidding_group_energy_offer].data;
        stage,
        scenario,
        subscenario,
        multiply_by = MW_to_GW(),
    )
    return nothing
end
