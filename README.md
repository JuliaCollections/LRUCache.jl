# LRUCache.jl

[![Build Status](https://travis-ci.org/jcrist/LRUCache.jl.svg)](https://travis-ci.org/jcrist/LRUCache.jl)

Provides an implementation of a Least Recently Used (LRU) Cache for Julia.

An LRU Cache is a useful associative data structure that has a set maximum
size. Once that size is reached, the least recently used items are removed
first.

Note that this package requires the new
[Nullable](http://julia.readthedocs.org/en/latest/manual/types/#nullable-types-representing-missing-values)
types feature, and thus doesn't work with Julia 0.3 (the current release).

## Interface

`LRU` supports the standard `Associative` interface. Some examples of common
operations are shown below:

**Creation**

```julia
lru = LRU{K, V}([, maxsize=100])
```

Create an LRU Cache with maximum size `maxsize`. If `maxsize` is not provided,
a default of `100` is used.

**Add an item to the cache**

```julia
setitem!(lru, key, value)
lru[key] = value
```

**Lookup an item in the cache**

```julia
getitem(lru, key)
lru[key]
```

**Change the maxsize**

```julia
resize!(lru, size)
```

**Empty the cache**

```julia
empty!(lru)
```

### Caching Use

To effectively use `LRU` as a cache, several functions and macros have been
defined that allow for easy checking if an item is present, and if not quickly
calculating a default.

#### get!(lru::LRU, key, default)

Returns the value stored in `lru` for `key` if present. If not, stores `key =>
default`, and returns `default`.


#### get!(default::Callable, lru::LRU, key)

Like above, except if `key` is not present, stores `key => default()`, and
returns the result. This is intended to be used in `do` block syntax:

```julia
get!(lru, key) do
   ...
end
```

#### @get!(lru::LRU, key, default)

The `do` block syntax of `get!` is nice, but can be slow due to how Julia
currently handles anonymous functions. The `@get!` macro is an attempt to get
around this issue. It takes 3 parameters: the cache, a key to lookup, and a
default.  Note that as this is handled with meta-programming, the default can
be *anything that can be set as the right-hand-side of an assignment*. Example.

```julia
const lru = LRU{Float64, Int}()

_foo(a::Float64) = ...    # Some long-running calculation that returns an Int

function foo(a::Float64)
    @get! lru a _foo(a)
end
```

This expands (roughly) to:

```julia
function foo(a::Float64)
    return begin
        if haskey(lru, a)
            value = lru[a]
        else
            value = _foo(a)
            lru[a] = value
        end
        value
    end
end
```

The same can be done with a constant default value, or a `begin` block:

```julia
const lru = LRU{Int, Int}()

function fib(a::Int)
    @get! lru a begin
        if a < 2
            a
        else
            fib(a - 1) + fib(a - 2)
        end
    end
end
```

## Example

Commonly, you may have some long running function that sometimes gets called
with the same parameters more than once. As such, it may benefit from cacheing
the results.

Here's our example, long running calculation:

```julia
function foo(a::Float64, b::Float64)
    sleep(100)
    result = a * b
end
```

As this function requires more than one parameter, we need a cache from
`(Float64, Float64)` to `Float64`. A cached version is then:

```julia
const lru = LRU{(Float64, Float64), Float64}()

function cached_foo(a::Float64, b::Float64)
    @get! lru (a, b) foo(a, b)
end
```
