
# julia test suite for size

using Test

using ProbStitch: Corpus, size

@testset "make sure corpus is sized correctly" begin
    @test size(Corpus(["a", "b"])) == 2
    @test size(Corpus(["a", "b", "c"])) == 3
    @test size(Corpus(["a", "b", "c", "d"])) == 4
    @test size(Corpus(String[])) == 0
end

@testset "test size of s expressions" begin
    @test size(Corpus(["(a)"])) == 1
    @test size(Corpus(["(a b c (d))"])) == 4
    @test size(Corpus(["((a b))"])) == 2
    @test size(Corpus(["(((a b)))"])) == 2
end
