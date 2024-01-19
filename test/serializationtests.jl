using Serialization
@testset "Serialize and Deserialize" begin

    cache = LRU{Int, Int}(maxsize=100_000)

    # Populate the cache with dummy data
    num_entries_to_test = [0, 1, 2, 3, 4, 5, 100_000, 1_000_000]
    for i in 0:maximum(num_entries_to_test)
        i ∈ num_entries_to_test || continue
        io = IOBuffer()
        serialize(io, cache)
        seekstart(io)
        deserialized_cache = deserialize(io)

        # Check that the cache is the same
        @test cache.maxsize == deserialized_cache.maxsize
        @test cache.currentsize == deserialized_cache.currentsize
        @test cache.hits == deserialized_cache.hits
        @test cache.misses == deserialized_cache.misses
        @test cache.by == deserialized_cache.by
        @test cache.finalizer == deserialized_cache.finalizer
        @test cache.keyset.length == deserialized_cache.keyset.length
        @test issetequal(collect(cache), collect(deserialized_cache))
        # Check that the cache has the same keyset
        @test length(cache.keyset) == length(deserialized_cache.keyset)
        @test all(((c_val, d_val),) -> c_val == d_val, zip(cache.keyset, deserialized_cache.keyset))
        # Check that the cache keys, values, and sizes are the same
        for (key, (c_value, c_node, c_s)) in cache.dict
            d_value, d_node, d_s = deserialized_cache.dict[key]
            c_value == d_value || @test false
            c_node.val == d_node.val || @test false
            c_s == d_s || @test false
        end
        cache[i] = i+1
    end
end
