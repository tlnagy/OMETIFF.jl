using OMETIFF
using FileIO
using AxisArrays
using Base.Test

@testset "Single file OME-TIFFs" begin
    @testset "Single Channel OME-TIFF" begin
        open("testdata/singles/single-channel.ome.tif") do f
            s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
            img = OMETIFF.load(s)
            @test size(img) == (167, 439)
        end
    end
    @testset "Multi Channel OME-TIFF" begin
        open("testdata/singles/multi-channel.ome.tif") do f
            s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
            img = OMETIFF.load(s)
            @test size(img) == (167, 439, 3)
            # check channel indexing
            @test size(img[Axis{:channel}(:C1)]) == (167, 439)
        end
    end
    @testset "Multi Channel Time Series OME-TIFF" begin
        open("testdata/singles/multi-channel-time-series.ome.tif") do f
            s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
            img = OMETIFF.load(s)
            @test size(img) == (167, 439, 3, 7)
            # check channel indexing
            @test size(img[Axis{:channel}(:C1)]) == (167, 439, 7)
            # check time indexing
            @test size(img[Axis{:time}(1)]) == (167, 439, 3)
        end
    end
    @testset "Multi Channel Z Series OME-TIFF" begin
        open("testdata/singles/multi-channel-z-series.ome.tif") do f
            s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
            img = OMETIFF.load(s)
            @test size(img) == (167, 439, 5, 3)
            # check channel indexing
            @test size(img[Axis{:channel}(:C1)]) == (167, 439, 5)
            # check z indexing
            @test size(img[Axis{:z}(1)]) == (167, 439, 3)
        end
    end
end
@testset "Multi file OME-TIFFs" begin
    @testset "Multi file Z stack with master file" begin
        # load the master file that contains the full OME-XML
        @testset "Load master file)" begin
            open("testdata/multiples/master/multifile-Z1.ome.tiff") do f
                s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
                img = OMETIFF.load(s)
                @test size(img) == (24, 18, 5)
            end
        end
        # load the secondary file that only has a pointer to the full OME-XML
        @testset "Load secondary file" begin
            open("testdata/multiples/master/multifile-Z2.ome.tiff") do f
                s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
                img = OMETIFF.load(s)
                @test size(img) == (24, 18, 5)
            end
        end
    end
    @testset "Multi file Z stack with OME companion file" begin
        open("testdata/multiples/companion/multifile-Z1.ome.tiff") do f
            s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
            img = OMETIFF.load(s)
            @test size(img) == (24, 18, 5)
        end
    end
end
