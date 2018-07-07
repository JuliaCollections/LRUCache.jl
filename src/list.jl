mutable struct LRUNode{K, V}
    k::K
    v::V
    next::LRUNode{K, V}
    prev::LRUNode{K, V}

    # All new created nodes are self referential only
    function LRUNode{K, V}(k::K, v::V) where {K, V}
        x = new{K, V}(k, v)
        x.next = x
        x.prev = x
        return x
    end
end

mutable struct LRUList{K, V}
    first::Union{LRUNode{K, V}, Nothing}
    size::Int

    LRUList{K, V}() where {K, V} = new{K, V}(nothing, 0)
end

Base.first(l::LRUList) = !isempty(l) ? l.first : error("LRUList is empty")
Base.last(l::LRUList) = !isempty(l) ? l.first.prev : error("LRUList is empty")

Base.length(l::LRUList) = l.size
Base.isempty(l::LRUList) = length(l) == 0

function Base.show(io::IO, l::LRUNode{K, V}) where {K, V}
    print(io, "LRUNode{", K, ", ", V, "}(")
    show(io, l.k)
    print(io, ", ")
    show(io, l.v)
    print(io, ")")
end

function Base.show(io::IO, l::LRUList{K, V}) where {K, V}
    print(io, "LRUList{", K, ", ", V, "}(")
    if length(l) != 0
        f = first(l)
        show(io, f.k)
        print(io, "=>")
        show(io, f.v)
        n = f.next
        while n !== f
            print(io, ", ")
            show(io, n.k)
            print(io, "=>")
            show(io, n.v)
            n = n.next
        end
    end
    print(io, ")")
end

function Base.push!(list::LRUNode{K, V}, new::LRUNode{K, V}) where {K, V}
    new.next = list
    new.prev = list.prev
    list.prev.next = new
    list.prev = new
    return list
end

function Base.push!(l::LRUList{K, V}, el::LRUNode{K, V}) where {K, V}
    if isempty(l)
        l.first = el
    else
        push!(first(l), el)
    end
    l.size += 1
    return l
end

function Base.pop!(l::LRUList{K, V}, n::LRUNode{K, V}=last(l)) where {K, V}
    if n.next === n
        l.first = nothing
    else
        if n === first(l)
            l.first = n.next
        end
        n.next.prev = n.prev
        n.prev.next = n.next
    end
    l.size -= 1
    return n
end

function Base.unshift!(l::LRUList{K, V}, el::LRUNode{K, V}) where {K, V}
    push!(l, el)
    rotate!(l)
end

# Rotate one step forward, so last element is now first
function rotate!(l::LRUList)
    if length(l) > 1
        l.first = first(l).prev
    end
    return l
end

# Move the node n to the front of the list
function move_to_front!(l::LRUList{T}, n::LRUNode{T}) where {T}
    if first(l) !== n
        pop!(l, n)
        unshift!(l, n)
    end
    return l
end

function Base.delete!(l::LRUList{K, V}, n::LRUNode{K, V}) where {K, V}
    pop!(l, n)
    return l
end

function Base.empty!(l::LRUList{K, V}) where {K, V}
    l.first = nothing
    l.size = 0
    return l
end
