using Serialization
@testset "Serialize and Deserialize" begin

    cache = LRU{Int, Int}(maxsize=100_000)

    # Populate the cache with dummy data
    for i in 1:1_000_000
        cache[i] = i+1
    end
    serialize("cache.jls", cache)
    deserialized_cache = deserialize("cache.jls")
    rm("cache.jls")

    # Check that the cache is the same
    @test cache.maxsize == deserialized_cache.maxsize
    @test cache.currentsize == deserialized_cache.currentsize
    @test cache.hits == deserialized_cache.hits
    @test cache.misses == deserialized_cache.misses
    @test cache.by == deserialized_cache.by
    @test cache.finalizer == deserialized_cache.finalizer
    @test cache.keyset.length == deserialized_cache.keyset.length
    @test length(cache.dict) == length(deserialized_cache.dict)
    # Check that the cache has the same keyset
    c_node = cache.keyset.first
    d_node = deserialized_cache.keyset.first
    for i in 1:cache.keyset.length
        c_node.val == d_node.val || @test false
        c_node = c_node.next
        d_node = d_node.next
    end
    # Check that the cache keys, values, and sizes are the same
    for (key, (c_value, c_node, c_s)) in cache.dict
        d_value, d_node, d_s = deserialized_cache.dict[key]
        c_value == d_value || @test false
        c_node.val == d_node.val || @test false
        c_s == d_s || @test false
    end
end

