using Test
using DeepLittre
using XML

function parse_tei(fragment::AbstractString)::XML.Node
	document = XML.parse(XML.Node, "<fragment>$(fragment)</fragment>")
	document[end]
end

tei_descendants(node::XML.Node, name::String)::Vector{XML.Node} =
	DeepLittre.iter_descendants(node, name)

tei_attribute(node::XML.Node, key::String)::String = DeepLittre.attr(node, key)

tei_child(node::XML.Node, name::String)::XML.Node = DeepLittre.find_child(node, name)

function tei_text(node::XML.Node)::String
	buffer = IOBuffer()
	function gather(current)
		if XML.nodetype(current) == XML.Text
			print(buffer, XML.value(current))
		elseif XML.nodetype(current) == XML.Element
			children = XML.children(current)
			children === nothing || foreach(gather, children)
		end
	end
	gather(node)
	String(take!(buffer))
end

tei_with_attribute(node::XML.Node, name::String, key::String, value::String)::Vector{XML.Node} =
	[child for child in tei_descendants(node, name) if tei_attribute(child, key) == value]

function tei_only(node::XML.Node, name::String, key::String, value::String)::XML.Node
	matches = tei_with_attribute(node, name, key, value)
	@test length(matches) == 1
	first(matches)
end
