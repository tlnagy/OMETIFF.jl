"""
    to_symbol(input) -> String

Cleans up `input` string and converts it into a symbol, needed so that channel
names work with AxisArrays.
"""
function to_symbol(input::String)
    fixed = replace(input, r"[^\w\ \-\_]"=>"")
    fixed = replace(fixed, r"[\ \-\_]+"=>"_")
    Symbol(replace(fixed, r"^[\d]"=>s"_\g<0>"))
end

"""
    shift!(d, δ, o)

Given an `OrderedDict` d, shifts all keys greater than or equal to `o` by `δ`.
Preserves original order.

```jldoctest
julia> d = OrderedDict(vcat(6 => 'F', 1:5 .=> 'A':'E'))
OrderedDict{Int64, Char} with 6 entries:
  6 => 'F'
  1 => 'A'
  2 => 'B'
  3 => 'C'
  4 => 'D'
  5 => 'E'

julia> shift!(d, 1, 3)

julia> d
OrderedDict{Int64, Char} with 6 entries:
  7 => 'F'
  1 => 'A'
  2 => 'B'
  4 => 'C'
  5 => 'D'
  6 => 'E'
```
"""
function shift!(d::OrderedDict{Int, S}, δ::Int, o::Int) where S
    ks = Int[]
    vs = S[]
    shift = Bool[]

    for k in keys(d)
        push!(ks, k)
        push!(vs, pop!(d, k))
        push!(shift, k >= o) # if shifting is needed for this item
    end

    for (k,v,s) in zip(ks, vs, shift)
        # if shift needed, update key
        d[s ? k + δ : k] = v
    end
end