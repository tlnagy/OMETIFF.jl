(Sys.islinux() || Sys.iswindows()) && import ImageMagick # work around libz issues
using OMETIFF
using FileIO
using Unitful
using AxisArrays
using Test

include("utils.jl")

@testset "TiffData Layouts" begin
    include("tiffdatas.jl")
end

@testset "Elapsed Time" begin
    include("elapsedtime.jl")
end

@testset "Axes Values" begin
    open("testdata/singles/181003_multi_pos_time_course_1_MMStack.ome.tif") do f
        s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
        img = OMETIFF.load(s)
        # check that the first three axes are length, length, time
        @test all(dimension.(first.(axisvalues(img)[1:3])) .== (u"𝐋", u"𝐋", u"𝐓"))
        # check the value of the 3rd index along the y axis
        @test axisvalues(img)[1][3] == 10.4608u"μm"
    end
end

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
    # tests whether slices in the multi-dimensional array returned by OMETIFF.jl
    # are correctly indexed
    # see https://github.com/tlnagy/OMETIFF.jl/issues/19
    @testset "Intercalated IFDs, issue #19" begin
        open("testdata/singles/181003_multi_pos_time_course_1_MMStack.ome.tif") do f
            s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
            img = OMETIFF.load(s)
            # verify against slices made in Fiji
            for pos in [1, 2]
                for tp in 0:9
                    # load Fiji-made slices
                    tiffslice = open("testdata/singles/181003_slices/P$(pos)_T$(tp).tif") do s
                        FileIO.load(Stream(format"TIFF", s, OMETIFF.extract_filename(s)))
                    end
                    omeslice = img[Axis{:position}(pos), Axis{:time}(tp+1)].data
                    # verify that ometiff slices are correctly indexed
                    @testset "Testing P$(pos)_T$(tp).tif" begin
                        @test all(omeslice .== tiffslice)
                    end
                end
            end
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

@testset "Loader arguments" begin
    # verify that disabling dropping unused dimensions works as expected
    @testset "Drop unused dimensions" begin
        open(joinpath("testdata", "multiples", "companion", "multifile-Z1.ome.tiff")) do f
            s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
            img = OMETIFF.load(s, dropunused=false)
            @test size(img) == (24, 18, 1, 1, 5, 1)
        end
    end
    @testset "Memory mapping" begin
        open(joinpath("testdata", "singles", "181003_multi_pos_time_course_1_MMStack.ome.tif")) do f
            s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
            img = OMETIFF.load(s, inmemory=false)
            img2 = OMETIFF.load(s)
            @test size(img) == (256, 256, 10, 2)
            @test all(img[1:10,1,1,1] .== img2[1:10,1,1,1])
            # file is read only and should throw an error if you try and modify it
            @test_throws ErrorException img[1:10,1,1,1] .= 1.0
        end
    end
end

@testset "Error checks" begin
    @test_throws FileIO.LoaderError load(File(format"OMETIFF", joinpath("testdata", "nonometif.tif")))
end

@testset "OMEXML dump test" begin
    expected = """<OME xmlns=\"http://www.openmicroscopy.org/Schemas/OME/2016-06\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" Creator=\"OME Bio-Formats 5.2.2\" UUID=\"urn:uuid:2bc2aa39-30d2-44ee-8399-c513492dd5de\" xsi:schemaLocation=\"http://www.openmicroscopy.org/Schemas/OME/2016-06 http://www.openmicroscopy.org/Schemas/OME/2016-06/ome.xsd\">\n  <Image ID=\"Image:0\" Name=\"single-channel.ome.tif\">\n    <Pixels BigEndian=\"true\" DimensionOrder=\"XYZCT\" ID=\"Pixels:0\" SizeC=\"1\" SizeT=\"1\" SizeX=\"439\" SizeY=\"167\" SizeZ=\"1\" Type=\"int8\">\n      <Channel ID=\"Channel:0:0\" SamplesPerPixel=\"1\">\n        <LightPath/>\n      </Channel>\n      <TiffData FirstC=\"0\" FirstT=\"0\" FirstZ=\"0\" IFD=\"0\" PlaneCount=\"1\">\n        <UUID FileName=\"single-channel.ome.tif\">urn:uuid:2bc2aa39-30d2-44ee-8399-c513492dd5de</UUID>\n      </TiffData>\n    </Pixels>\n  </Image>\n</OME>"""
    @test OMETIFF.dump_omexml(joinpath("testdata", "singles", "single-channel.ome.tif")) == expected
end

@testset "Issue #60" begin
    open(joinpath("testdata", "singles", "nonstriped_rect", "MMStack_Pos0.ome.tif")) do f
        s = Stream(format"OMETIFF", f, OMETIFF.extract_filename(f))
        img = OMETIFF.load(s)
        @test size(img) == (2160, 2560, 8)
    end
end