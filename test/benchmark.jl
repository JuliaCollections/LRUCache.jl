module Benchmark
using LRUCache

# This benchmark is a simple recursive Fibonnaci calculation. While not
# comparable to most real world problems, the simplicity of the underlying
# calculation means that most of the time is spent in the cacheing operations,
# rather than on the function itself. Which is optimal for comparing
# improvements to the cache speed.

const FIBCACHE = LRU{Int, Int}(10)

function fib(a::Int)
    @get! FIBCACHE a begin
        if a < 2
            a
        else
            fib(a - 1) + fib(a - 2)
        end
    end
end

function fib_benchmark(cachesize)
    resize!(FIBCACHE, cachesize)
    empty!(FIBCACHE)
    println("Cache Size = $cachesize")
    @time fib(50)
end

println("========== BENCHMARKS ==========")
println()

println("Toss this timing, things are still compiling")
fib_benchmark(5)
println()
println("Fibonnaci Benchmarks")
println("--------------------")
for n in (10, 50, 100)
    fib_benchmark(n)
end
println()

# Now we benchmark individual operations
function setup_cache(cachesize, items)
    resize!(FIBCACHE, cachesize)
    empty!(FIBCACHE)
    for i in items
        FIBCACHE[i] = i
    end
end
function benchmark_get(n)
    @time FIBCACHE[n]
end
function benchmark_set(k, v)
    @time FIBCACHE[k] = v
end

println("Access Benchmarks")
println("-----------------")
# Cache is [10, 9, 8, ...., 1] in order of use, and is full
setup_cache(10, 1:10)
println("Access for elements at head of cache")
for i in 1:5
    benchmark_get(10)
end
println()

# Cache is [10, 9, 8, ...., 1] in order of use, and is full
println("Access for elements not at head of cache")
for i in 1:5
    benchmark_get(i)
end
println()

println("Insertion Benchmarks")
println("--------------------")
# Cache is empty, with size 5
resize!(FIBCACHE, 5)
empty!(FIBCACHE)
println("Insertion when cache is not full, element not in cache")
for i in 1:5
    benchmark_set(i, i)
end
println()

# Cache is [5, 4, 3, 2, 1]
println("Insertion when element already in cache, not at head")
for i in 1:5
    benchmark_set(i, i)
end
println()

# Cache is [5, 4, 3, 2, 1]
println("Insertion when element already in cache, at head")
for i in 1:5
    benchmark_set(5, 5)
end
println()

# Cache is [5, 4, 3, 2, 1]
println("Insertion when cache is full, element not in cache")
for i in 6:10
    benchmark_set(i, i)
end

end
