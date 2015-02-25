module Tests

using LRUCache
using Base.Test

function test_order(lru, keys, vals)
    if length(lru) != 0
        f = first(lru.q)
        @test f.k == keys[1]
        @test f.v == vals[1]
        n = f.next
        i = 2
        while !is(n, f)
            @test n.k == keys[i]
            @test n.v == vals[i]
            i += 1
            n = n.next
        end
    end
end

const CACHE = LRU{Int, Int}(20)
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
resize!(CACHE, 5)
test_order(CACHE, kvs[1:5], kvs[1:5])

resize!(CACHE, 10)
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

# Test @get! with begin block
val = @get! CACHE 3 begin
    4
end
@test val == 4
@get! CACHE 3 begin
    error("this shouldn't have been called!")
end

# Test Abstract typed cache. All we're checking for here is that the container
# is able to hold abstract types without issue. Insertion order is already
# tested above.
const CACHE2 = LRU{String, Integer}(5)
CACHE2["test"] = 4
CACHE2[utf8("test2")] = BigInt(5)
@test CACHE2["test"] == 4
@test CACHE2["test2"] == 5

end
