# LRUCache.jl

[![Build Status](https://travis-ci.org/JuliaCollections/LRUCache.jl.svg)](https://travis-ci.org/JuliaCollections/LRUCache.jl)
[![License](http://img.shields.io/badge/license-MIT-brightgreen.svg?style=flat)](LICENSE.md)
[![codecov.io](http://codecov.io/github/JuliaCollections/LRUCache.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaCollections/LRUCache.jl?branch=master)

Provides a thread-safe implementation of a Least Recently Used (LRU) Cache for Julia.

An LRU Cache is a useful associative data structure (`AbstractDict` in Julia) that has a
set maximum size (as measured by number of elements or a custom size measure for items).
Once that size is reached, the least recently used items are removed first. A lock ensures
that data access does not lead to race conditions.

A particular use case of this package is to implement function memoization for functions
that can simultaneously be called from different threads.

## Installation
Install with the package manager via `]add LRUCache` or
```julia
using Pkg
Pkg.add("LRUCache")
```

## Interface

`LRU` supports the standard `AbstractDict` interface. Some examples of common
operations are shown below:

**Creation**

```julia
lru = LRU{K, V}(, maxsize = size [, by = ...])
```

Create an LRU Cache with a maximum size (number of items) specified by the *required*
keyword argument `maxsize`. Here, the size can be the number of elements (default), or the
maximal total size of the values in the dictionary, as counted by an arbitrary user
function (which should return a single value of type `Int`) specified with the keyword
argument `by`. Sensible choices would for example be `by = sizeof` for e.g. values which
are `Array`s of bitstypes, or `by = Base.summarysize` for values of some arbitrary user
type.

**Add an item to the cache**

```julia
setindex!(lru, value, key)
lru[key] = value
```

**Lookup an item in the cache**

```julia
getindex(lru, key)
lru[key]
```

**Change the maxsize**

```julia
resize!(lru; maxsize = size)
```

Here, the maximal size is specified via a required keyword argument. Remember that the
maximal size is not necessarily the same as the maximal length, if a custom function was
specified using the keyword argument `by` in the construction of the LRU cache.

**Empty the cache**

```julia
empty!(lru)
```

### Caching Use

To effectively use `LRU` as a cache, several functions from the `AbstractDict` interface
can be used for easy checking if an item is present, and if not quickly calculating a
default.

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

#### get(lru::LRU, key, default)

Returns the value stored in `lru` for `key` if present. If not, returns default without
storing this value in `lru`. Also comes in the following form:

#### get(default::Callable, lru::LRU, key)

## Example

Commonly, you may have some long running function that sometimes gets called with the same
parameters more than once. As such, it may benefit from caching the results.

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
const lru = LRU{Tuple{Float64, Float64}, Float64}()

function cached_foo(a::Float64, b::Float64)
    get!(lru, (a, b)) do
      foo(a,b)
    end
end
```
