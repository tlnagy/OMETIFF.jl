using OMETIFF
using AxisArrays
using Base.Test

@testset "Small OME-TIFFs" begin
    @testset "Single Channel OME-TIFF" begin
        img = OMETIFF.loadtiff("testdata/tiffs/single-channel.ome.tif")
        @test size(img) == (167, 439)
    end
    @testset "Multi Channel OME-TIFF" begin
        img = OMETIFF.loadtiff("testdata/tiffs/multi-channel.ome.tif")
        @test size(img) == (167, 439, 3)
        # check channel indexing
        @test size(img[Axis{:channel}(:C1)]) == (167, 439)
    end
    @testset "Multi Channel Time Series OME-TIFF" begin
        img = OMETIFF.loadtiff("testdata/tiffs/multi-channel-time-series.ome.tif")
        @test size(img) == (167, 439, 3, 7)
        # check channel indexing
        @test size(img[Axis{:channel}(:C1)]) == (167, 439, 7)
        # check time indexing
        @test size(img[Axis{:time}(1)]) == (167, 439, 3)
    end
    @testset "Multi Channel Time Series OME-TIFF" begin
        img = OMETIFF.loadtiff("testdata/tiffs/multi-channel-z-series.ome.tif")
        @test size(img) == (167, 439, 5, 3)
        # check channel indexing
        @test size(img[Axis{:channel}(:C1)]) == (167, 439, 5)
        # check z indexing
        @test size(img[Axis{:z}(1)]) == (167, 439, 3)
    end
end
