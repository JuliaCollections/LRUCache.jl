using LRUCache
using Test
using Random
using Base.Threads

# Test insertion and reinsertion ordering
@testset "Single-threaded insertion and reinsertion" begin
    for cache in [LRU(; maxsize = 100), LRU{Int, Int}(; maxsize = 100)]
        r = 1:100
        for i in reverse(r)
            cache[i] = i
        end
        @test collect(cache) == collect(i=>i for i in r)

        for i = 1:10:100
            @test haskey(cache, i)
            @test !haskey(cache, 100+i)
        end

        # reinsert in random order
        p = randperm(100)
        for i in reverse(p)
            cache[i] = i
        end
        @test collect(cache) == collect(i=>i for i in p)
    end
end

@testset "Multi-threaded insertion and reinsertion" begin
    cache = LRU{Int, Int}(; maxsize = 100)

    r = 1:100
    @threads for i in reverse(r)
        cache[i] = i
    end

    @threads for i = 1:10:100
        @test haskey(cache, i)
        @test !haskey(cache, 100+i)
    end

    @test Set(cache) == Set(i=>i for i=1:100)

    @threads for i in 100:-1:1
        cache[i] = 2*i
    end

    @test Set(cache) == Set(i=>2*i for i=1:100)
end

@testset "Single-threaded getting and setting" begin
    cache = LRU{Int, Int}(; maxsize = 50*sizeof(Int), by = sizeof)

    for i in 100:-1:1
        @test 2*i == get(cache, i, 2*i)
        @test 2*i == get(()->2*i, cache, i)
        @test i == (iseven(i) ? get!(cache, i, i) : get!(()->i, cache, i))
        @test i == get!(cache, i, 2*i)
        @test i == get!(()->error("this should not happen"), cache, i)
        @test i == get(cache, i, 2*i)
        @test i == get(()->2*i, cache, i)
    end
    for i in 1:50
        @test haskey(cache, i)
        @test !haskey(cache, i+50)
        @test_throws KeyError getindex(cache, i+50)
    end

    @test collect(cache) == collect(i=>i for i in 1:50)

    p = randperm(50)
    for i in reverse(p)
        cache[i] = i
    end
    @test collect(cache) == collect(i=>i for i in p)

    p10 = p[1:10]
    resize!(cache; maxsize = 10*sizeof(Int))
    @test collect(cache) == collect(i=>i for i in p10)

    resize!(cache; maxsize = 50*sizeof(Int))
    @test collect(cache) == collect(i=>i for i in p10)

    for i in 50:-1:1
        @test get!(cache, i, 2*i) == (i in p10 ? i : 2*i)
    end

    for i in reverse(p10)
        @test cache[i] == i
    end
    resize!(cache; maxsize = 10*sizeof(Int))
    @test collect(cache) == collect(i=>i for i in p10)

    delete!(cache, p10[1])
    @test !haskey(cache, p10[1])

    @test p10[10] == pop!(cache, p10[10])
    @test !haskey(cache, p10[10])

    @test length(empty!(cache)) == 0
    @test isempty(cache)
    for i in p10
        @test !haskey(cache, p10)
    end
end

@testset "Multi-threaded getting and setting" begin
    cache = LRU{Int, Int}(; maxsize = 50*sizeof(Int), by = sizeof)

    @threads for i in 50:-1:1
        @test 2*i == get(cache, i, 2*i)
        @test 2*i == get(()->2*i, cache, i)
        @test i == (iseven(i) ? get!(cache, i, i) : get!(()->i, cache, i))
        @test i == get!(cache, i, 2*i)
        @test i == get!(()->error("this should not happen"), cache, i)
        @test i == get(cache, i, 2*i)
        @test i == get(()->2*i, cache, i)
    end

    p = randperm(50)
    p10 = p[1:10]
    @threads for i in p10
        @test cache[i] == i
    end
    resize!(cache; maxsize = 10*sizeof(Int))
    @test Set(cache) == Set(i=>i for i in p10)

    resize!(cache; maxsize = 50*sizeof(Int))
    @test Set(cache) == Set(i=>i for i in p10)

    delete!(cache, p10[1])
    @test !haskey(cache, p10[1])
    @test_throws KeyError getindex(cache, p10[1])

    @test p10[10] == pop!(cache, p10[10])
    @test !haskey(cache, p10[10])
    @test_throws KeyError getindex(cache, p10[1])
end

@testset "Recursive lock in get(!)" begin
    cache = LRU{Int,Int}(; maxsize = 100)
    p = randperm(100)
    cache[1] = 1

    f!(cache, i) = get!(()->(f!(cache, i-1) + 1), cache, i)
    @threads for i = 1:100
        f!(cache, p[i])
    end

    @threads for i = 1:100
        @test haskey(cache, i)
        @test cache[i] == i
    end
end

@testset "Eviction callback" begin
    # Julia 1.0 and 1.1 crash with multiple threads on this
    # combination of @threads and Channel.
    if VERSION >= v"1.2" || Threads.nthreads() == 1
        resources = Channel{Matrix{Float64}}(11)
        for _ = 1:11
            put!(resources, zeros(5, 5))
        end
        callback = (key, value) -> put!(resources, value)
        cache = LRU{Int,Matrix{Float64}}(; maxsize = 10, finalizer = callback)

        @threads for i = 1:100
            cache[i ÷ gcd(i, 60)] = take!(resources)
        end
        # Note: It's not ideal to rely on the Channel internals but there
        # doesn't seem to be a public way to check how much is occupied.
        @test length(resources.data) == 1
        cache[101] = take!(resources)
        @test length(resources.data) == 1
        pop!(cache, 101)
        @test length(resources.data) == 2
        cache[101] = take!(resources)
        @test length(resources.data) == 1
        delete!(cache, 101)
        @test length(resources.data) == 2
        get!(cache, 101, take!(resources))
        @test length(resources.data) == 1
        get!(() -> take!(resources), cache, 102)
        @test length(resources.data) == 1
        get!(() -> take!(resources), cache, 102)
        @test length(resources.data) == 1
        resize!(cache, maxsize = 5)
        @test length(resources.data) == 6
        empty!(cache)
        @test length(resources.data) == 11
        @test cache.maxsize == 5
    end
end

@testset "Reverse iterator" begin
    lru = LRU(;maxsize = 4)
    # Instantiate lazy reverse iterator
    rlru = Iterators.reverse(lru)
    # Did we handle the empty cache?
    @test [k => v for (k,v) in lru] == []
    @test [k => v for (k,v) in rlru] == []
    # Fill in some data
    lru["first"] = 1
    # Does a single element cache work
    @test [k => v for (k,v) in lru] == ["first" => 1]
    @test [k => v for (k,v) in rlru] == ["first" => 1]
    lru["second"] = 2
    # Does a partially filled cache work
    @test [k => v for (k,v) in lru] == ["second" => 2, "first" => 1]
    @test [k => v for (k,v) in rlru] == ["first" => 1, "second" => 2]
    lru["third"] = 3
    lru["fourth"] = 4
    # Does forward iteration give us the expected result?
    @test [k => v for (k,v) in lru] == ["fourth" => 4, "third" => 3, "second" => 2, "first" => 1]
    @test [k => v for (k,v) in rlru] == ["first" => 1, "second" => 2, "third" => 3, "fourth" => 4]
    # Evict first by inserting fifth
    lru["fifth"] = 5
    @test [k => v for (k,v) in lru] == ["fifth" => 5, "fourth" => 4, "third" => 3, "second" => 2]
    @test [k => v for (k,v) in rlru] == ["second" => 2, "third" => 3, "fourth" => 4, "fifth" => 5]
end

# https://github.com/JuliaCollections/LRUCache.jl/issues/37
@testset "Large entries" begin
    lru = LRU{Int, Vector{Int}}(; maxsize=10, by=length)
    get!(lru, 1, 1:9)
    @test !isempty(lru)
    @test lru[1] == 1:9

    # Add too-big entry
    get!(lru, 2, 1:11)
    # did not add entry 2, it is too big
    @test !haskey(lru, 2)

    # Still have old entries
    @test !isempty(lru)
    @test lru[1] == 1:9

    # Same with `setindex!`
    lru[2] = 1:11
    @test !haskey(lru, 2)
    @test !isempty(lru)
    @test lru[1] == 1:9

    # Add a second small entry
    lru[2] = 1:1
    @test haskey(lru, 2)
    @test lru[1] == 1:9
    @test lru[2] == 1:1

    # Re-assign it to a too-big entry
    lru[2] = 1:11
    @test !haskey(lru, 2) # don't keep the old entry!
    @test lru[1] == 1:9
end

include("originaltests.jl")
