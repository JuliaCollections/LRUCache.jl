using LRUCache
using Test
using Random
using Base.Threads

# Test insertion and reinsertion ordering
@testset "Single-threaded insertion and reinsertion" begin
    cache = LRU{Int, Int}(; maxsize = 100)

    r = 1:100
    for i in reverse(r)
        cache[i] = i
    end
    @test collect(cache) == collect(i=>i for i in r)

    @threads for i = 1:10:100
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

include("originaltests.jl")
