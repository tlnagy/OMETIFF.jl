using EzXML
using UUIDs
using TiffImages
"""
ref:
    https://docs.openmicroscopy.org/ome-model/5.6.3/ome-tiff/specification.html
    https://micro-manager.org/wiki/Micro-Manager_File_Formats
    https://github.com/ome/ome-model/blob/master/ome_model/experimental.py
"""

"""
New and set attribute node one by one
"""
function set_attributes!(node::EzXML.Node, attrs::AbstractDict)
    for (name, value) in attrs
        attr = AttributeNode(string(name), string(value))
        link!(node, attr)
    end
end


"""
New and link element node to parent node
"""
function new_child(node_parent::EzXML.Node, name::AbstractString)
    node_child = ElementNode(name)
    link!(node_parent, node_child)
end


"""
Add text node to element node
"""
function add_text!(node::EzXML.Node, txt::AbstractString)
    txt_node = TextNode(txt)
    link!(node, txt_node)
end

"""
Create and return OME XML string with xyzt
"""
function generatexml(FileName::String, SizeX::Integer, SizeY::Integer, SizeZ::Integer, SizeT::Integer)
    OMEDoc = XMLDocument();
    OME = ElementNode("OME");
    setroot!(OMEDoc, OME)
    xmlns="http://www.openmicroscopy.org/Schemas/OME/2016-06" 
    xmlns_xsi="http://www.w3.org/2001/XMLSchema-instance"
    Creator="OME Bio-Formats 5.2.2" 
    OME_UUID="urn:uuid:"*string(uuid4()) 
    xsi_schemaLocation="http://www.openmicroscopy.org/Schemas/OME/2016-06 http://www.openmicroscopy.org/Schemas/OME/2016-06/ome.xsd"
    OME_attributes = Dict("xmlns"=>xmlns, "xmlns:xsi"=>xmlns_xsi, "Creator"=>Creator, "UUID"=>OME_UUID, 
                          "xsi:schemaLocation"=>xsi_schemaLocation)
    set_attributes!(OME, OME_attributes)
    
    name = FileName
    Image= ElementNode("Image")
    Image = new_child(OME, "Image")
    set_attributes!(Image, Dict("ID"=>"Image:0", "Name"=>FileName))
    
    Pixels = new_child(Image, "Pixels");
    SizeC=1; 
    PhysicalSizeX=PhysicalSizeY=0.108; PhysicalSizeZ=0.5;
    TimeIncrement=600;
    Pixels_attributes = Dict("ID"=>"Pixels:0","Type"=>"uint16", "BigEndian"=>"false",
    "DimensionOrder"=>"XYZCT", "SizeC"=>SizeC,"SizeX"=>SizeX, "SizeY"=>SizeY, "SizeZ"=>SizeZ, "SizeT"=>SizeT,
    "PhysicalSizeX"=>PhysicalSizeX, "PhysicalSizeY"=>PhysicalSizeY, "PhysicalSizeZ"=>PhysicalSizeZ,
    "PhysicalSizeXUnit"=>"µm", "PhysicalSizeYUnit"=>"µm", "PhysicalSizeZUnit"=>"µm",
    "TimeIncrement"=>TimeIncrement, "TimeIncrementUnit"=>"s");
    set_attributes!(Pixels, Pixels_attributes)
    
    Channel_ = new_child(Pixels, "Channel");
    set_attributes!(Channel_, Dict("ID"=>"Channel:0:0", "SamplesPerPixel"=>"1"));
    LightPath =new_child(Channel_, "LightPath");
    
	for c in 0:SizeC-1
    	for t in 0:SizeT-1
        	for z in 0:SizeZ-1
               TiffData = new_child(Pixels, "TiffData")
               TiffData_attributes = Dict("FirstC"=>c, "FirstT"=>t, "FirstZ"=>z, 
										  "IFD"=>t*SizeZ+z,"PlaneCount"=>1)
                set_attributes!(TiffData, TiffData_attributes)
                TiffUUID = new_child(TiffData, "UUID")
                add_text!(TiffUUID ,OME_UUID)
                TiffUUID_attrs = Dict("FileName"=>FileName)
                set_attributes!(TiffUUID, TiffUUID_attrs)
            end
        end
    end
    OMEDoc;
end


"""
Here is a writer for 4D OMETIFF , waiting to be cleaned and generalized.
"""
function save(FileName::AbstractString, omeimg::ImageMeta)
    # Generate OMEXML based on metadata
    x, y, z, t = size(omeimg)
    data = reshape(arraydata(omeimg.data),x, y, :)
    saved_tiff = TiffImages.DenseTaggedImage(data);
    saved_OMEXML = generatexml(FileName, x, y, z, t)
    # Embed generated omexml to first idfs IMAGEDESCRIPTION
    # ISSUE: if we don't change metadata, it should remain orignal OMEXML or copy from previous ome container
    first(saved_tiff.ifds)[IMAGEDESCRIPTION] = string(saved_OMEXML)
    # ISSUE: I don't know how to link TiffImages.save()
    TiffImages.save(FileName, saved_tiff)
end
