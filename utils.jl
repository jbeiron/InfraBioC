# Utility functions for data manipulation, file I/O, and parameter construction.

export expand_range, make_symbols
using CSV, DataFrames, XLSX, JuMP

should_keep(v; drop_zeros=true, atol=1e-8) = (!drop_zeros) || (!isfinite(v) ? true : abs(v) > atol)

function df_1d(x, I; name_i::Symbol=:i, name_v::Symbol=:value, drop_zeros=true, atol=1e-8)
    rows = NamedTuple[]
    for i in I
        v = value(x[i])
        if should_keep(v; drop_zeros=drop_zeros, atol=atol)
            push!(rows, (name_i => i, name_v => v))
        end
    end
    DataFrame(rows)
end

function df_3d(x, A, B, C; nA=:a, nB=:b, nC=:c, nV=:value, drop_zeros=true, atol=1e-8)
    rows = NamedTuple[]
    for a in A, b in B, c in C
        v = value(x[a,b,c])
        if should_keep(v; drop_zeros=drop_zeros, atol=atol)
            push!(rows, (nA => a, nB => b, nC => c, nV => v))
        end
    end
    DataFrame(rows)
end

function df_4d(x, A, B, C, D; nA=:a, nB=:b, nC=:c, nD=:d, nV=:value, drop_zeros=true, atol=1e-8)
    rows = NamedTuple[]
    for a in A, b in B, c in C, d in D
        v = value(x[a,b,c,d])
        if should_keep(v; drop_zeros=drop_zeros, atol=atol)
            push!(rows, (nA => a, nB => b, nC => c, nD => d, nV => v))
        end
    end
    DataFrame(rows)
end

function df_5d(x, A, B, C, D, E; nA=:a, nB=:b, nC=:c, nD=:d, nE=:e, nV=:value, drop_zeros=true, atol=1e-8)
    rows = NamedTuple[]
    for a in A, b in B, c in C, d in D, e in E
        v = value(x[a,b,c,d,e])
        if should_keep(v; drop_zeros=drop_zeros, atol=atol)
            push!(rows, (nA => a, nB => b, nC => c, nD => d, nE => e, nV => v))
        end
    end
    DataFrame(rows)
end

function write_df_to_sheet!(xf, sheetname::AbstractString, df::DataFrame)
    XLSX.addsheet!(xf, sheetname)
    sh = xf[sheetname]
    XLSX.writetable!(sh, Tables.columntable(df); header=names(df))
    return nothing
end


function expand_range(spec::AbstractString)::Vector{Symbol}
    parts = split(spec, '*')
    length(parts) == 2 || error("Not a range spec: $spec")
    a, b = parts[1], parts[2]

    m1 = match(r"^(.*?)(\d+)$", a)
    m2 = match(r"^(.*?)(\d+)$", b)
    (m1 !== nothing && m2 !== nothing) || error("Range endpoints must end with digits: $spec")

    p1, i1 = m1.captures[1], parse(Int, m1.captures[2])
    p2, i2 = m2.captures[1], parse(Int, m2.captures[2])
    p1 == p2 || error("Prefix mismatch in range: $spec")

    return [Symbol(p1 * string(k)) for k in i1:i2]
end

function make_symbols(items::Vector{String})::Vector{Symbol}
    out = Symbol[]
    for raw in items
        for token in split(raw, ',')
            s = strip(token)
            isempty(s) && continue
            if occursin('*', s)
                append!(out, expand_range(s))
            else
                push!(out, Symbol(s))
            end
        end
    end
    return out
end



function get_df(file_path::AbstractString; sheet::Union{Nothing,String}=nothing)
    xf = XLSX.readxlsx(file_path)
    sheet_name = sheet === nothing ? XLSX.sheetnames(xf)[1] : sheet
    # infer_eltypes=false minskar “överraskningar” i indexkolumner
    return DataFrame(XLSX.readtable(file_path, sheet_name; infer_eltypes=false))
end

# säkrare än String(x) när x kan vara Float64/Int/etc.
to_str_or_missing(x) = ismissing(x) ? missing : string(x)

function read_file(file_path::AbstractString;
                   sheet::Union{Nothing,String}=nothing,
                   index_cols::Vector{Symbol}=Symbol[])
    df =
        if endswith(lowercase(file_path), ".xlsx") || endswith(lowercase(file_path), ".xls")
            get_df(file_path; sheet=sheet)
        elseif endswith(lowercase(file_path), ".csv")
            CSV.read(file_path, DataFrame; normalizenames=true)
        else
            error("Unsupported file format. Please provide XLSX/XLS or CSV file.")
        end

    # Normalisera kolumnnamn till Symbols som matchar CSV normalizenames
    rename!(df, Symbol.(names(df)))

    # Konvertera bara indexkolumnerna till String (eller missing)
    for c in index_cols
        if c in names(df)
            df[!, c] = to_str_or_missing.(df[!, c])
        end
    end

    return df
end

# Hjälp: parse Float64 från "svensk" text, tomt -> missing
function parse_float_or_missing(x)
    if ismissing(x)
        return missing
    end
    s = strip(string(x))
    isempty(s) && return missing
    s = replace(s, "," => ".")
    return parse(Float64, s)
end

# Hjälp: normalisera indexvärden till Symbol
tosym_or_missing(x) = ismissing(x) ? missing : Symbol(strip(string(x)))

function build_param_2d(df::DataFrame, col_i::Symbol, col_j::Symbol, col_v::Symbol;
                        as_symbol_index::Bool=true, allow_missing_value::Bool=false)
    p = Dict{Tuple{Any,Any},Float64}()
    for r in eachrow(df)
        i = as_symbol_index ? tosym_or_missing(r[col_i]) : r[col_i]
        j = as_symbol_index ? tosym_or_missing(r[col_j]) : r[col_j]
        v = parse_float_or_missing(r[col_v])
        if i === missing || j === missing
            error("Missing index in columns $(col_i), $(col_j)")
        end
        if v === missing
            if allow_missing_value
                continue
            else
                error("Missing value for index ($(i), $(j)) in column $(col_v)")
            end
        end
        p[(i,j)] = v
    end
    return p
end

function coerce_index_to_symbol!(df::DataFrame, cols::Vector{Symbol})
    for c in cols
        c in names(df) || continue
        df[!, c] = tosym_or_missing.(df[!, c])
    end
    return df
end

function coerce_numeric!(df::DataFrame, cols::Vector{Symbol})
    for c in cols
        c in names(df) || continue
        df[!, c] = parse_float_or_missing.(df[!, c])
    end
    return df
end

function dict_2d(df::DataFrame,
                 col_i::Symbol,
                 col_j::Symbol,
                 col_v::Symbol;
                 allow_missing::Bool=false)

    p = Dict{Tuple{Symbol,Symbol},Float64}()

    for (k, r) in enumerate(eachrow(df))
        i = r[col_i]
        j = r[col_j]
        v = r[col_v]

        if ismissing(i) || ismissing(j)
            error("Missing index at row $k: ($i, $j)")
        end

        vv = parse_float_or_missing(v)
        if vv === missing
            if allow_missing
                continue
            else
                error("Missing/empty value at row $k for key ($(i), $(j))")
            end
        end

        # Säkerställ Symbol-index (om df ibland innehåller String)
        ii = i isa Symbol ? i : Symbol(strip(string(i)))
        jj = j isa Symbol ? j : Symbol(strip(string(j)))

        p[(ii, jj)] = vv
    end

    return p
end

function load_wide_param_2d(input_dir::AbstractString,
                            filename::AbstractString;
                            index_col::Symbol,
                            prop_col::Symbol,
                            sheet::Union{Nothing,String}=nothing)

    path = joinpath(input_dir, filename)

    # 1) Read file; force index column to String so it can be cleanly symbolized
    df = read_file(path; sheet=sheet, index_cols=[index_col])

    # 2) Normalize column names (TECH -> :tech, C_inv -> :c_inv, etc.)
    rename!(df, Symbol.(lowercase.(string.(names(df)))))

    # IMPORTANT: index_col was lowercased by rename!, so adjust:
    idx = Symbol(lowercase(string(index_col)))

    # 3) Wide -> long
    df_long = stack(df, Not(idx); variable_name=prop_col, value_name=:value)

    # 4) Normalize indices to Symbol
    df_long[!, idx] = Symbol.(strip.(string.(df_long[!, idx])))
    df_long[!, prop_col] = Symbol.(strip.(string.(df_long[!, prop_col])))

    # 5) Build Dict
    return dict_2d(df_long, idx, prop_col, :value)
end


