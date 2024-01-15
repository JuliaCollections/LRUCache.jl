module SerializationExt
using LRUCache
using Serialization

# Serialization of large LRUs causes a stack overflow error, so we 
# create a custom serializer that represents LinkedNodes as Ints
function Serialization.serialize(s::AbstractSerializer, lru::LRU{K, V}) where {K, V}
    # Create a mapping from memory address to id
    node_map = IdDict{LRUCache.LinkedNode{K}, Int}()
    # Create mapping for first node
    id = 1
    first_node = node = lru.keyset.first
    node_map[node] = id
    # Go through the rest of the nodes in the cycle and create a mapping
    node = node.next
    while node != first_node
        id += 1
        node_map[node] = id
        node = node.next
    end
    @assert id == length(lru) == lru.keyset.length == length(lru.dict)
    # By this point, the first node has id 1 and the last node has id length(lru)
    # so when deserializing, we can infer the order by the id
    # Create the dict with ids instead of nodes
    dict = Dict{K, Tuple{V, Int, Int}}()
    for (key, (value, node, s)) in lru.dict
        id = node_map[node]
        dict[key] = (value, id, s)
    end
    Serialization.writetag(s.io, Serialization.OBJECT_TAG)
    Serialization.serialize(s, typeof(lru))
    Serialization.serialize(s, dict)
    Serialization.serialize(s, lru.currentsize)
    Serialization.serialize(s, lru.maxsize)
    Serialization.serialize(s, lru.hits)
    Serialization.serialize(s, lru.misses)
    Serialization.serialize(s, lru.lock)
    Serialization.serialize(s, lru.by)
    Serialization.serialize(s, lru.finalizer)
end

function Serialization.deserialize(s::AbstractSerializer, ::Type{LRU{K, V}}) where {K, V}
    dict_with_ids = Serialization.deserialize(s)
    currentsize = Serialization.deserialize(s)
    maxsize = Serialization.deserialize(s)
    hits = Serialization.deserialize(s)
    misses = Serialization.deserialize(s)
    lock = Serialization.deserialize(s)
    by = Serialization.deserialize(s)
    finalizer = Serialization.deserialize(s)
    # Create a new keyset and mapping from id to node
    n_nodes = length(dict_with_ids)
    nodes = Vector{LRUCache.LinkedNode{K}}(undef, n_nodes)
    dict = Dict{K, Tuple{V, LRUCache.LinkedNode{K}, Int}}()
    # Create the nodes, but don't link them yet
    for (key, (value, id, s)) in dict_with_ids
        nodes[id] = LRUCache.LinkedNode{K}(key)
        dict[key] = (value, nodes[id], s)
    end
    # Link the nodes
    for (idx, node) in enumerate(nodes)
        node.next = nodes[mod1(idx+1, n_nodes)]
        node.prev = nodes[mod1(idx-1, n_nodes)]
    end
    # Create keyset with first node and n_nodes
    keyset = LRUCache.CyclicOrderedSet{K}()
    keyset.first = nodes[1]
    keyset.length = n_nodes
    # Create LRU
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
