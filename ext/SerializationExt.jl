module SerializationExt
using LRUCache
using Serialization

function Serialization.serialize(s::AbstractSerializer, lru::LRU{K, V}) where {K, V}
    Serialization.writetag(s.io, Serialization.OBJECT_TAG)
    serialize(s, typeof(lru))
    @assert lru.currentsize == length(lru)
    serialize(s, lru.currentsize)
    serialize(s, lru.maxsize)
    serialize(s, lru.hits)
    serialize(s, lru.misses)
    serialize(s, lru.lock)
    serialize(s, lru.by)
    serialize(s, lru.finalizer)
    for (k, val) in lru
        serialize(s, k)
        serialize(s, val)
    end
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{LRU{K, V}}) where {K, V}
    currentsize = Serialization.deserialize(s)
    maxsize = Serialization.deserialize(s)
    hits = Serialization.deserialize(s)
    misses = Serialization.deserialize(s)
    lock = Serialization.deserialize(s)
    by = Serialization.deserialize(s)
    finalizer = Serialization.deserialize(s)

    dict = Dict{K, Tuple{V, LRUCache.LinkedNode{K}, Int}}()
    sizehint!(dict, currentsize)
    # Create node chain
    first = nothing
    node = nothing
    for i in 1:currentsize
        prev = node
        k = deserialize(s)
        node = LRUCache.LinkedNode{K}(k)
        val = deserialize(s)
        sz = by(val)::Int
        dict[k] = (val, node, sz)
        if i == 1 
            first = node
            continue
        else
            prev.next = node
            node.prev = prev
        end
    end
    # close the chain if any node exists
    if !isnothing(node)
        node.next = first
        first.prev = node
    end

    # Createa cyclic ordered set from the node chain
    keyset = LRUCache.CyclicOrderedSet{K}()
    keyset.first = first
    keyset.length = currentsize

    # Create the LRU
    lru = LRU{K,V}(maxsize=maxsize)
    lru.dict = dict
    lru.keyset = keyset
    lru.currentsize = currentsize
    lru.hits = hits
    lru.misses = misses
    lru.lock = lock
    lru.by = by
    lru.finalizer = finalizer
    lru
end
end
