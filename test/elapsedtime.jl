@testset "Only T axis" begin
    planes = []

    dims = (X=512, Y=512, Z=1, C=1, T=10, P=1)
    axes = [Axis{:x}(), Axis{:y}(), Axis{:z}(), Axis{:channel}(1), Axis{:time}(1:10), Axis{:position}(1)]

    for t=0:9
        push!(planes, """<Plane DeltaT="$(t*10.0)" DeltaTUnit="ms" TheC="0" TheT="$t" TheZ="0"/>""")
    end
    container = root(parsexml(wrap(join(planes, "\n\t"))))

    @test all(OMETIFF.get_elapsed_times([container], dims, axes; default_unit=Unitful.ms).data .== collect(0:10:90)*u"ms")
end

@testset "Missing DeltaT" begin
    planes = []

    dims = (X=512, Y=512, Z=1, C=1, T=10, P=1)
    axes = [Axis{:x}(), Axis{:y}(), Axis{:z}(), Axis{:channel}(1), Axis{:time}(1:10), Axis{:position}(1)]

    for t=0:9
        push!(planes, """<Plane TheC="0" TheT="$t" TheZ="0"/>""")
    end
    container = root(parsexml(wrap(join(planes, "\n\t"))))

    @test all(isnan.(OMETIFF.get_elapsed_times([container], dims, axes; default_unit=Unitful.ms)))
end

@testset "Multiple dimensions" begin
    planes = []

    dims = (X=512, Y=512, Z=1, C=2, T=10, P=3)
    axes = [Axis{:x}(), Axis{:y}(), Axis{:z}(), Axis{:channel}(1:2), Axis{:time}(1:10), Axis{:position}(1:3)]

    containers = EzXML.Node[]
    for p in 1:3
        for t in 1:10, c in 1:2
            push!(planes, """<Plane DeltaT="$(t*p*c)" TheC="$(c-1)" TheT="$(t-1)" TheZ="0"/>""")
        end
        push!(containers, root(parsexml(wrap(join(planes, "\n\t")))))
    end

    output = OMETIFF.get_elapsed_times(containers, dims, axes; default_unit=Unitful.ms)
    @test all(size(output) .== (2, 10, 3))
    @test all(output[Axis{:position}(2), Axis{:channel}(1)] .== collect(2:2:20.0)*u"ms")
end

@testset "Mixed units" begin
    planes = []

    dims = (X=512, Y=512, Z=1, C=1, T=10, P=1)
    axes = [Axis{:x}(), Axis{:y}(), Axis{:z}(), Axis{:channel}(1), Axis{:time}(1:10), Axis{:position}(1)]

    for t in 1:10
        unit = "ms"
        (iseven(t)) && (unit = "s")
        push!(planes, """<Plane DeltaT="$((t+1)÷2*10.0)" DeltaTUnit="$unit" TheC="0" TheT="$(t-1)" TheZ="0"/>""")
    end
    container = root(parsexml(wrap(join(planes, "\n\t"))))

    output = OMETIFF.get_elapsed_times([container], dims, axes; default_unit=Unitful.ms)
    @test all(output[1:2:end]*1000 .== output[2:2:end]) # the evens are in seconds so they should be 1000 times the odd values
end