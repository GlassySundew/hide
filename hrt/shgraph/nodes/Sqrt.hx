package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Square Root")
@description("The output is the squre root A")
@width(120)
@group("Math")
@:keep
class Sqrt extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(0.0) var a : Dynamic;
		@sgoutput var output : Dynamic;
		function fragment() {
			output = sqrt(a);
		}
	};

}