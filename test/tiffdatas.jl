using EzXML
using DataStructures

# Tests for TiffData adapted from
# https://docs.openmicroscopy.org/ome-model/5.5.4/ome-tiff/specification.html

function get_result(ifd_index, ifd_files, dimlist)
    io = IOBuffer()
    sort!(ifd_index)
    for (idx, ifd) in ifd_index
        (ifd == nothing) && continue
        # get dimensions corresponding to the right image
        # the last index in ifd is position
        dims = dimlist[ifd[end]]
        println(io, idx-1, "\tZ", ifd[loc(dims, :Z)]-1, "-T", ifd[loc(dims, :T)]-1, "-C", ifd[loc(dims, :C)]-1)
    end
    String(take!(io));
end

loc(dims, dimname) = findfirst(isequal(dimname), keys(dims))-2

function get_ifds(fragment)
    omexml = root(parsexml(wrap(fragment)))
    containers = findall("//*[@DimensionOrder]", omexml)
    n_ifds = 0
    dimlist = []
    for container in containers
        dims, _ = OMETIFF.build_axes(container)
        push!(dimlist, dims)
        n_ifds += dims[:Z]*dims[:C]*dims[:T]
    end
    ifd_index = OrderedDict{Int, NTuple{4, Int}}()
    ifd_files = OrderedDict{Int, Tuple{String, String}}()
    obs_filepaths = Set{String}()
    for (idx, container) in enumerate(containers)
        OMETIFF.ifdindex!(ifd_index, ifd_files, obs_filepaths, container, dimlist[idx], "", idx)
    end
    ifd_index, ifd_files, dimlist
end

@testset "Multiple planes per TiffData" begin
    @testset "Empty TiffData" begin
        fragment1 = """
        <Pixels ID="urn:lsid:loci.wisc.edu:Pixels:ows325"
                Type="uint8" DimensionOrder="XYZTC"
                SizeX="512" SizeY="512" SizeZ="3" SizeT="2" SizeC="2">
            <TiffData/>
        </Pixels>
        """

        expected = """
        0	Z0-T0-C0
        1	Z1-T0-C0
        2	Z2-T0-C0
        3	Z0-T1-C0
        4	Z1-T1-C0
        5	Z2-T1-C0
        6	Z0-T0-C1
        7	Z1-T0-C1
        8	Z2-T0-C1
        9	Z0-T1-C1
        10	Z1-T1-C1
        11	Z2-T1-C1
        """

        @test get_result(get_ifds(fragment1)...) == expected
    end

    @testset "Multiple planes" begin
        fragment2 = """
        <Pixels ID="urn:lsid:loci.wisc.edu:Pixels:ows462"
                Type="uint8" DimensionOrder="XYCTZ"
                SizeX="512" SizeY="512" SizeZ="4" SizeT="3" SizeC="2">
            <TiffData PlaneCount="10"/>
        </Pixels>
        """

        expected2 = """
        0	Z0-T0-C0
        1	Z0-T0-C1
        2	Z0-T1-C0
        3	Z0-T1-C1
        4	Z0-T2-C0
        5	Z0-T2-C1
        6	Z1-T0-C0
        7	Z1-T0-C1
        8	Z1-T1-C0
        9	Z1-T1-C1
        """

        @test get_result(get_ifds(fragment2)...) == expected2
    end

    @testset "Offset IFD, multiple planes" begin
        fragment3 = """
        <Pixels ID="urn:lsid:loci.wisc.edu:Pixels:ows197"
                Type="uint8" DimensionOrder="XYZTC"
                SizeX="512" SizeY="512" SizeZ="4" SizeC="3" SizeT="2">
            <TiffData IFD="3" PlaneCount="5"/>
        </Pixels>
        """

        expected3 = """
        3	Z0-T0-C0
        4	Z1-T0-C0
        5	Z2-T0-C0
        6	Z3-T0-C0
        7	Z0-T1-C0
        """

        @test get_result(get_ifds(fragment3)...) == expected3
    end
end

@testset "Reverse temporal order" begin
    fragment4 = """
    <Pixels ID="urn:lsid:loci.wisc.edu:Pixels:ows789"
            Type="uint8" DimensionOrder="XYZTC"
            SizeX="512" SizeY="512" SizeZ="1" SizeC="1" SizeT="6">
        <TiffData IFD="0" FirstT="5"/>
        <TiffData IFD="1" FirstT="4"/>
        <TiffData IFD="2" FirstT="3"/>
        <TiffData IFD="3" FirstT="2"/>
        <TiffData IFD="4" FirstT="1"/>
        <TiffData IFD="5" FirstT="0"/>
    </Pixels>
    """

    expected4 = """
    0	Z0-T5-C0
    1	Z0-T4-C0
    2	Z0-T3-C0
    3	Z0-T2-C0
    4	Z0-T1-C0
    5	Z0-T0-C0
    """

    @test get_result(get_ifds(fragment4)...) == expected4
end


@testset "Different pixel dimensions" begin
    fragment5 = """
    <Pixels ID="urn:lsid:loci.wisc.edu:Pixels:ows789"
            Type="uint8" DimensionOrder="XYZTC"
            SizeX="512" SizeY="512" SizeZ="1" SizeC="1" SizeT="6">
        <TiffData IFD="0" FirstT="5"/>
        <TiffData IFD="2" FirstT="4"/>
        <TiffData IFD="4" FirstT="3"/>
        <TiffData IFD="6" FirstT="2"/>
        <TiffData IFD="7" FirstT="1"/>
        <TiffData IFD="8" FirstT="0"/>
    </Pixels>
    <Pixels ID="urn:lsid:loci.wisc.edu:Pixels:ows789"
            Type="uint8" DimensionOrder="XYZTC"
            SizeX="512" SizeY="512" SizeZ="1" SizeC="1" SizeT="3">
        <TiffData IFD="1" FirstT="1"/>
        <TiffData IFD="3" FirstT="2"/>
        <TiffData IFD="5" FirstT="3"/>
    </Pixels>
    """

    expected5 = """
    0	Z0-T5-C0
    1	Z0-T1-C0
    2	Z0-T4-C0
    3	Z0-T2-C0
    4	Z0-T3-C0
    5	Z0-T3-C0
    6	Z0-T2-C0
    7	Z0-T1-C0
    8	Z0-T0-C0
    """
    @test get_result(get_ifds(fragment5)...) == expected5
end

@testset "Missing IFDs" begin

    fragment6 = """
    <Pixels BigEndian="false" DimensionOrder="XYCZT" ID="Pixels:0" PhysicalSizeX="5.2304" PhysicalSizeXUnit="µm" PhysicalSizeY="5.2304" PhysicalSizeYUnit="µm" SizeC="1" SizeT="10" SizeX="256" SizeY="256" SizeZ="1" TimeIncrement="5000.0" TimeIncrementUnit="ms" Type="uint16">
    <Channel ID="Channel:0:0" Name="Default" SamplesPerPixel="1">
        <LightPath/>
    </Channel>
    <TiffData FirstC="0" FirstT="0" FirstZ="0" IFD="0" PlaneCount="1">
        <UUID FileName="181003_multi_pos_time_course_1_MMStack.ome.tif">urn:uuid:3872d873-e5a6-421b-a3a2-4d6539f77442</UUID>
    </TiffData>
    <TiffData FirstC="0" FirstT="1" FirstZ="0" IFD="1" PlaneCount="1">
        <UUID FileName="181003_multi_pos_time_course_1_MMStack.ome.tif">urn:uuid:3872d873-e5a6-421b-a3a2-4d6539f77442</UUID>
    </TiffData>
    <TiffData FirstC="0" FirstT="2" FirstZ="0" IFD="2" PlaneCount="1">
        <UUID FileName="181003_multi_pos_time_course_1_MMStack.ome.tif">urn:uuid:3872d873-e5a6-421b-a3a2-4d6539f77442</UUID>
    </TiffData>
    <TiffData FirstC="0" FirstT="3" FirstZ="0" IFD="3" PlaneCount="1">
        <UUID FileName="181003_multi_pos_time_course_1_MMStack.ome.tif">urn:uuid:3872d873-e5a6-421b-a3a2-4d6539f77442</UUID>
    </TiffData>
    </Pixels>
    """

    ifd_index, ifd_files, dimlist = get_ifds(fragment6)

    @test all(map(i->ifd_index[i], 1:4) .== [(1, 1, 1, 1), (1, 1, 2, 1), (1, 1, 3, 1), (1, 1, 4, 1)])
    @test length(ifd_index) .== 4
end

@testset "IFD Index Sharing" begin

    fragment7 = """
    <Pixels BigEndian="false" DimensionOrder="XYCTZ" ID="Pixels:0:0" Type="uint8" SizeC="1" SizeT="1" SizeX="18" SizeY="24" SizeZ="5">
    <Channel Color="-2147483648" ID="Channel:0"/>
    <TiffData FirstC="0" FirstT="0" FirstZ="0" IFD="0" PlaneCount="1">
        <UUID FileName="multifile-Z1.ome.tiff">urn:uuid:d25bfea2-2708-4a4f-bcd9-8ab1ac478041</UUID>
    </TiffData>
    <TiffData FirstC="0" FirstT="0" FirstZ="1" IFD="0" PlaneCount="1">
        <UUID FileName="multifile-Z2.ome.tiff">urn:uuid:7f283a5c-828e-4dec-955f-1e5ed26773b6</UUID>
    </TiffData>
    <TiffData FirstC="0" FirstT="0" FirstZ="2" IFD="0" PlaneCount="1">
        <UUID FileName="multifile-Z3.ome.tiff">urn:uuid:e3bdd73e-d2a8-4999-9135-b8422265ba18</UUID>
    </TiffData>
    <TiffData FirstC="0" FirstT="0" FirstZ="3" IFD="0" PlaneCount="1">
        <UUID FileName="multifile-Z4.ome.tiff">urn:uuid:be142aa6-c8d8-40cb-9494-7ef5123308ff</UUID>
    </TiffData>
    <TiffData FirstC="0" FirstT="0" FirstZ="4" IFD="0" PlaneCount="1">
        <UUID FileName="multifile-Z5.ome.tiff">urn:uuid:38731a88-9908-4aec-8df3-18d63c0d24dd</UUID>
    </TiffData>
    </Pixels>
    """

    ifd_index, ifd_files, dimlist = get_ifds(fragment7)

    @test all(collect(values(ifd_index)) .== [(1, 1, 1, 1), (1, 1, 2, 1), (1, 1, 3, 1), (1, 1, 4, 1), (1, 1, 5, 1)])
end