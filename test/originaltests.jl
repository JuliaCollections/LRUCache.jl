@testset "Original tests" begin

function test_order(lru, keys, vals)
    for (i, (k,v)) = enumerate(lru)
        @test k == keys[i]
        @test v == vals[i]
    end
end

CACHE = LRU{Int, Int}(; maxsize = 20)
# Test insertion ordering
kvs = 1:10
for i in reverse(kvs)
    CACHE[i] = i
end
test_order(CACHE, 1:10, 1:10)

# Test reinsertion ordering
kvs = [1, 3, 5, 7, 9, 2, 4, 6, 8, 10]
for i in reverse(kvs)
    CACHE[i] = i
end
test_order(CACHE, kvs, kvs)

# Test least recently used items are evicted
resize!(CACHE; maxsize = 5)
test_order(CACHE, kvs[1:5], kvs[1:5])

resize!(CACHE; maxsize = 10)
test_order(CACHE, kvs[1:5], kvs[1:5])

kvs = 1:11
for i in reverse(kvs)
    CACHE[i] = i
end
test_order(CACHE, kvs[1:end-1], kvs[1:end-1])

# Test lookups, and that lookups reorder
kvs = 1:10
for i in reverse(kvs)
    CACHE[i] = 2*i
end
for i in kvs
    @test CACHE[i] == 2*i
end
test_order(CACHE, reverse(kvs), reverse(2*kvs))

# Test empty!
empty!(CACHE)
@test length(CACHE) == 0

# Test get! with default parameter
@test get!(CACHE, 1, 2)  == 2    # not in cache
@test get!(CACHE, 1, 2)  == 2    # in cache

# Test get! with function call
val = get!(CACHE, 2) do
          3
      end
@test val == 3
get!(CACHE, 2) do
    error("this shouldn't have been called!")
end

# Test Abstract typed cache. All we're checking for here is that the container
# is able to hold abstract types without issue. Insertion order is already
# tested above.
CACHE2 = LRU{String, Integer}(; maxsize = 5)
CACHE2["test"] = 4
@test CACHE2["test"] == 4

end
