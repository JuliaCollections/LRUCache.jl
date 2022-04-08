using Base: HasEltype, HasLength, EltypeUnknown

mutable struct LinkedNode{T}
    val::T
    next::LinkedNode{T}
    prev::LinkedNode{T}

    # All new created nodes are self referential only
    function LinkedNode{T}(k::T) where {T}
        x = new{T}(k)
        x.next = x
        x.prev = x
        return x
    end
end

mutable struct CyclicOrderedSet{T} <: AbstractSet{T}
    first::Union{LinkedNode{T}, Nothing}
    length::Int

    CyclicOrderedSet{T}() where {T} = new{T}(nothing, 0)
end

CyclicOrderedSet(itr) = _CyclicOrderedSet(itr, IteratorEltype(itr))

_CyclicOrderedSet(itr, ::HasEltype) = CyclicOrderedSet{eltype(itr)}(itr)
function _CyclicOrderedSet(itr, ::EltypeUnknown)
    T = Base.@default_eltype(itr)
    (isconcretetype(T) || T === Union{}) || return grow_to!(CyclicOrderedSet{T}(), itr)
    return CyclicOrderedSet{T}(itr)
end
CyclicOrderedSet{T}(itr) where {T} = union!(CyclicOrderedSet{T}(), itr)

function Base.iterate(s::CyclicOrderedSet, state = s.first)
    if state === nothing
        return nothing
    else
        return state.val, state.next == s.first ? nothing : state.next
    end
end
Base.IteratorSize(::Type{<:CyclicOrderedSet}) = HasLength()
Base.IteratorEltype(::Type{<:CyclicOrderedSet}) = HasEltype()
Base.length(s::CyclicOrderedSet) = s.length
Base.isempty(s::CyclicOrderedSet) = length(s) == 0

Base.empty(s::CyclicOrderedSet{T}, ::Type{U}=T) where {T,U} = CyclicOrderedSet{U}()


function Base.show(io::IO, s::CyclicOrderedSet{T}) where {T}
    print(io, "CyclicOrderedSet{", T, "}(")
    if s.first !== nothing
        f = s.first
        show(io, f.val)
        n = f.next
        while n !== f
            print(io, ", ")
            show(io, n.val)
            n = n.next
        end
    end
    print(io, ")")
end

function _findnode(s::CyclicOrderedSet, x)
    isempty(s) && return nothing
    n = s.first
    while !isequal(n.val, x)
        n = n.next
        n == s.first && return nothing
    end
    return n
end

# adding items
function _push!(s::CyclicOrderedSet{T}, n::LinkedNode{T}) where {T}
    if isempty(s)
        s.first = n
    else
        list = s.first
        n.next = list
        n.prev = list.prev
        list.prev.next = n
        list.prev = n
    end
    s.length += 1
    return s
end
function Base.push!(s::CyclicOrderedSet{T}, x) where T
    n = _findnode(s, x)
    if n === nothing
        _push!(s, LinkedNode{T}(x))
    else
        _delete!(s, n)
        _push!(s, n)
    end
    return s
end
Base.pushfirst!(s::CyclicOrderedSet, x) = rotate!(push!(s, x))

# removing items
function _delete!(s::CyclicOrderedSet{T}, n::LinkedNode{T}) where {T}
    n.next.prev = n.prev
    n.prev.next = n.next
    s.length -= 1
    if n == s.first
        s.first = s.length == 0 ? nothing : n.next
    end
    return s
end
function Base.pop!(s::CyclicOrderedSet)
    isempty(s) && throw(ArgumentError("collection must be non-empty"))
    n = s.first.prev
    _delete!(s, n)
    return n.val
end
function Base.pop!(s::CyclicOrderedSet, x)
    n = _findnode(s, x)
    if n === nothing
        throw(KeyError(x))
    else
        _delete!(s, n)
        return x
    end
end
function Base.pop!(s::CyclicOrderedSet, x, default)
    n = _findnode(s, x)
    if n === nothing
        return default
    else
        _delete!(s, n)
        return x
    end
end
function Base.delete!(s::CyclicOrderedSet, x)
    n = _findnode(s, x)
    if n !== nothing
        _delete!(s, n)
    end
    return s
end
function Base.empty!(s::CyclicOrderedSet)
    s.first = nothing
    s.length = 0
    return s
end

# Rotate one step forward, so last element is now first
function rotate!(s::CyclicOrderedSet)
    if length(s) > 1
        s.first = s.first.prev
    end
    return s
end

function _move_to_front!(s::CyclicOrderedSet{T}, n::LinkedNode{T}) where {T}
    if s.first !== n
        n.next.prev = n.prev
        n.prev.next = n.next
        n.next = s.first
        n.prev = s.first.prev
        s.first.prev.next = n
        s.first.prev = n
        s.first = n
    end
    return s
end

# Reverse iterator for LRUCache.CyclicOrderedSet
Base.eltype(::Type{Iterators.Reverse{LRUCache.CyclicOrderedSet{T}}}) where {T} = eltype(T)
Base.IteratorSize(::Type{Iterators.Reverse{LRUCache.CyclicOrderedSet{T}}}) where {T} = Base.IteratorSize(LRUCache.CyclicOrderedSet)
Base.IteratorEltype(::Type{Iterators.Reverse{LRUCache.CyclicOrderedSet{T}}}) where {T} = Base.IteratorEltype(LRUCache.CyclicOrderedSet)
Base.last(r::Iterators.Reverse{LRUCache.CyclicOrderedSet{T}}) where {T} = first(r.itr)
Base.first(r::Iterators.Reverse{LRUCache.CyclicOrderedSet{T}}) where {T} = r.itr.first.prev.val

function Base.iterate(
    s::Iterators.Reverse{LRUCache.CyclicOrderedSet{T}}, 
    state = (s.itr.first isa Nothing) ? nothing : s.itr.first.prev
) where {T}
    if state === nothing
        return nothing
    else
        return state.val, state.prev.val == first(s) ? nothing : state.prev
    end
end
