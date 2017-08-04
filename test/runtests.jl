using OMETIFF
using FileIO
using AxisArrays
using Base.Test

@testset "Small OME-TIFFs" begin
    @testset "Single Channel OME-TIFF" begin
        open("testdata/tiffs/single-channel.ome.tif") do f
            s = Stream(format"OMETIFF", f, f.name)
            img = OMETIFF.load(s)
            @test size(img) == (167, 439)
        end
    end
    @testset "Multi Channel OME-TIFF" begin
        open("testdata/tiffs/multi-channel.ome.tif") do f
            s = Stream(format"OMETIFF", f, f.name)
            img = OMETIFF.load(s)
            @test size(img) == (167, 439, 3)
            # check channel indexing
            @test size(img[Axis{:channel}(:C1)]) == (167, 439)
        end
    end
    @testset "Multi Channel Time Series OME-TIFF" begin
        open("testdata/tiffs/multi-channel-time-series.ome.tif") do f
            s = Stream(format"OMETIFF", f, f.name)
            img = OMETIFF.load(s)
            @test size(img) == (167, 439, 3, 7)
            # check channel indexing
            @test size(img[Axis{:channel}(:C1)]) == (167, 439, 7)
            # check time indexing
            @test size(img[Axis{:time}(1)]) == (167, 439, 3)
        end
    end
    @testset "Multi Channel Time Series OME-TIFF" begin
        open("testdata/tiffs/multi-channel-z-series.ome.tif") do f
            s = Stream(format"OMETIFF", f, f.name)
            img = OMETIFF.load(s)
            @test size(img) == (167, 439, 5, 3)
            # check channel indexing
            @test size(img[Axis{:channel}(:C1)]) == (167, 439, 5)
            # check z indexing
            @test size(img[Axis{:z}(1)]) == (167, 439, 3)
        end
    end
end
