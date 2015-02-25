type LRUNode{K, V}
    k::K
    v::V
    next::LRUNode{K, V}
    prev::LRUNode{K, V}

    # All new created nodes are self referential only
    function LRUNode{K, V}(k::K, v::V)
        x = new(k, v)
        x.next = x
        x.prev = x
        return x
    end
end

type LRUList{K, V}
    first::Nullable{LRUNode{K, V}}
    size::Int

    LRUList() = new(Nullable{LRUNode{K, V}}(), 0)
end

Base.first(l::LRUList) = !isempty(l) ? get(l.first) : error("LRUList is empty")
Base.last(l::LRUList) = !isempty(l) ? get(l.first).prev : error("LRUList is empty")

Base.length(l::LRUList) = l.size
Base.isempty(l::LRUList) = length(l) == 0

function Base.show{K, V}(io::IO, l::LRUNode{K, V})
    print(io, "LRUNode{", K, ", ", V, "}(")
    show(io, l.k)
    print(io, ", ")
    show(io, l.v)
    print(io, ")")
end

function Base.show{K, V}(io::IO, l::LRUList{K, V})
    print(io, "LRUList{", K, ", ", V, "}(")
    if length(l) != 0
        f = first(l)
        show(io, f.k)
        print(io, "=>")
        show(io, f.v)
        n = f.next
        while !is(n, f)
            print(io, ", ")
            show(io, n.k)
            print(io, "=>")
            show(io, n.v)
            n = n.next
        end
    end
    print(io, ")")
end

function Base.push!{K, V}(list::LRUNode{K, V}, new::LRUNode{K, V})
    new.next = list
    new.prev = list.prev
    list.prev.next = new
    list.prev = new
    return list
end

function Base.push!{K, V}(l::LRUList{K, V}, el::LRUNode{K, V})
    if isempty(l)
        l.first = Nullable(el)
    else
        push!(first(l), el)
    end
    l.size += 1
    return l
end

function Base.pop!{K, V}(l::LRUList{K, V}, n::LRUNode{K, V}=last(l))
    if is(n.next, n)
        l.first = Nullable{LRUNode{K, V}}()
    else
        if is(n, first(l))
            l.first = Nullable(n.next)
        end
        n.next.prev = n.prev
        n.prev.next = n.next
    end
    l.size -= 1
    return n
end

function Base.unshift!{K, V}(l::LRUList{K, V}, el::LRUNode{K, V})
    push!(l, el)
    rotate!(l)
end

# Rotate one step forward, so last element is now first
function rotate!(l::LRUList)
    if length(l) > 1
        l.first = Nullable(first(l).prev)
    end
    return l
end

# Move the node n to the front of the list
function move_to_front!{T}(l::LRUList{T}, n::LRUNode{T})
    if !is(first(l), n)
        pop!(l, n)
        unshift!(l, n)
    end
    return l
end

function Base.delete!{K, V}(l::LRUList{K, V}, n::LRUNode{K, V})
    pop!(l, n)
    return l
end

function Base.empty!{K, V}(l::LRUList{K, V})
    l.first = Nullable{LRUNode{K, V}}()
    l.size = 0
    return l
end
