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
    @testset "Multi position OME-TIFF" begin
        open("testdata/singles/background_1_MMStack.ome.tif") do f
            s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
            img = OMETIFF.load(s)
            @test size(img) == (1024, 1024, 9)
            # check position indexing
            @test size(img[Axis{:position}(:Pos1)]) == (1024, 1024)
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
# let's make sure that the values we return are identical to normal TIFF readers
@testset "TIFF value verifications" begin
    files = [
        "testdata/singles/170918_tn_neutrophil_migration_wave.ome.tif",
        "testdata/singles/single-channel.ome.tif",
        "testdata/singles/background_1_MMStack.ome.tif"
    ]
    for filepath in files
        # open file using OMETIFF.jl
        ome = open(filepath) do f
            OMETIFF.load(Stream(format"OMETIFF", f, OMETIFF.extract_filename(f)))
        end
        # open file using standard TIFF parser
        tiff = open(filepath) do f
            FileIO.load(Stream(format"TIFF", f, OMETIFF.extract_filename(f)))
        end
        # compare
        @test all(ome.data .== tiff)
    end
end
