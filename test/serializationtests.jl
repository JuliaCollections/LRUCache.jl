using Serialization

function test_is_equivalent(a::LRU, b::LRU)
    # Check that the cache is the same
    @test a.maxsize == b.maxsize
    @test a.currentsize == b.currentsize
    @test a.hits == b.hits
    @test a.misses == b.misses
    @test a.by == b.by
    @test a.finalizer == b.finalizer
    @test a.keyset.length == b.keyset.length
    @test issetequal(collect(a), collect(b))
    # Check that the cache has the same keyset
    @test length(a.keyset) == length(b.keyset)
    @test all(((c_val, d_val),) -> c_val == d_val, zip(a.keyset, b.keyset))
    # Check that the cache keys, values, and sizes are the same
    for (key, (c_value, c_node, c_s)) in a.dict
        d_value, d_node, d_s = b.dict[key]
        c_value == d_value || @test false
        c_node.val == d_node.val || @test false
        c_s == d_s || @test false
    end
end

function roundtrip(lru::LRU)::LRU
    io = IOBuffer()
    serialize(io, lru)
    seekstart(io)
    deserialize(io)
end

@testset "Large Serialize and Deserialize" begin
    cache = LRU{Int, Int}(maxsize=100_000)

    # Populate the cache with dummy data
    num_entries_to_test = [0, 1, 2, 3, 4, 5, 100_000, 1_000_000]
    for i in 0:maximum(num_entries_to_test)
        # Add dummy data on all but the first iteration,
        # to test an empty cache
        i > 0 && (cache[i] = i+1)
        i ∈ num_entries_to_test || continue

        test_is_equivalent(cache, roundtrip(cache))
    end
end

@testset "Serialize mutable references" begin
    lru = LRU(; maxsize=5)
    a = b = [1]
    lru[1] = a
    lru[2] = b
    @test lru[1] === lru[2]
    lru2 = roundtrip(lru)
    @test lru2[1] === lru2[2]
end

@testset "Serialization with custom cache-size metric" begin
    lru = LRU{String,Vector{UInt8}}(; maxsize = 1024, by = sizeof)
    lru["a"] = rand(UInt8, 128)
    lru["b"] = rand(UInt8, 256)
    lru["c"] = rand(UInt8, 512)
    @test lru.currentsize == 896
    @test length(lru) == 3

    test_is_equivalent(lru, roundtrip(lru))
end
