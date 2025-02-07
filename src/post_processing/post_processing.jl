#  Copyright (c) 2024: PSR, CCEE (Câmara de Comercialização de Energia  
#      Elétrica), and contributors
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at https://mozilla.org/MPL/2.0/.
#############################################################################
# IARA
# See https://github.com/psrenergy/IARA.jl
#############################################################################

"""
    post_processing(inputs::Inputs)

Run post-processing routines.
"""
function post_processing(inputs::Inputs)
    Log.info("Running post-processing routines")
    post_proc_path = post_processing_path(inputs)
    if !isdir(post_proc_path)
        mkdir(post_proc_path)
    end

    outputs_post_processing = Outputs()
    model_outputs_time_series = TimeSeriesOutputs()
    run_time_options = RunTimeOptions(; is_post_processing = true)

    try
        post_process_outputs(inputs, outputs_post_processing, model_outputs_time_series, run_time_options)
    finally
        finalize_outputs!(outputs_post_processing)
        finalize_outputs!(model_outputs_time_series)
    end

    if inputs.args.plot_outputs
        build_plots(inputs)
    end
    return nothing
end

function post_process_outputs(
    inputs::Inputs,
    outputs_post_processing::Outputs,
    model_outputs_time_serie::TimeSeriesOutputs,
    run_time_options::RunTimeOptions,
)
    gather_outputs_separated_by_asset_owners(
        inputs,
        outputs_post_processing,
        model_outputs_time_serie,
        run_time_options,
    )
    if run_mode(inputs) == RunMode.TRAIN_MIN_COST
        post_processing_generation(inputs, outputs_post_processing, model_outputs_time_serie, run_time_options)
    end
    if is_market_clearing(inputs)
        create_bidding_group_generation_files(
            inputs,
            outputs_post_processing,
            model_outputs_time_serie,
            run_time_options,
        )
        if settlement_type(inputs) != IARA.Configurations_SettlementType.NONE
            post_processing_bidding_group_revenue(
                inputs,
                outputs_post_processing,
                model_outputs_time_serie,
                run_time_options,
            )
            if settlement_type(inputs) == IARA.Configurations_SettlementType.DUAL
                post_processing_bidding_group_total_revenue(
                    inputs,
                    outputs_post_processing,
                    model_outputs_time_serie,
                    run_time_options,
                )
            end
        end
    end

    return nothing
end

function open_time_series_output(
    inputs::Inputs,
    model_outputs::TimeSeriesOutputs,
    output_name::String;
    dir_path::String = output_path(inputs),
)
    file = joinpath(dir_path, output_name)
    reader = Quiver.Reader{Quiver.csv}(file)
    output_timeseries = QuiverInput(reader)
    model_outputs.outputs[output_name] = output_timeseries
    return reader
end

function get_writer(outputs::Outputs, output_name::String)
    return outputs.outputs[output_name].writer
end

function get_file_ext(filename::String)
    return splitext(filename)[2]
end

function get_filename(filename::String)
    return splitext(filename)[1]
end

# TODO: This should be on Quiver.jl
function sum_multiple_files(
    output_filename::String,
    filenames::Vector{String},
    impl::Type{<:Quiver.Implementation};
    digits::Union{Int, Nothing} = nothing,
)
    readers = [Quiver.Reader{impl}(filename) for filename in filenames]
    metadata = first(readers).metadata
    labels = metadata.labels

    writer = Quiver.Writer{impl}(
        output_filename;
        labels = labels,
        dimensions = string.(metadata.dimensions),
        time_dimension = string(metadata.time_dimension),
        dimension_size = metadata.dimension_size,
        initial_date = metadata.initial_date,
        unit = metadata.unit,
    )

    num_labels = length(metadata.labels)
    data = zeros(sum(num_labels))
    for dims in Iterators.product([1:size for size in reverse(metadata.dimension_size)]...)
        dim_kwargs = OrderedDict(metadata.dimensions .=> reverse(dims))
        fill!(data, 0)
        for reader in readers
            Quiver.goto!(reader; dim_kwargs...)
            data .+= reader.data
        end
        Quiver.write!(writer, Quiver.round_digits(data, digits); dim_kwargs...)
    end

    for reader in readers
        Quiver.close!(reader)
    end

    Quiver.close!(writer)
    return nothing
end
