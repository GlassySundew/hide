package hide.view.shadereditor;

import hrt.shgraph.nodes.SubGraph;
import hxsl.DynamicShader;
import h3d.Vector;
import hrt.shgraph.ShaderParam;
import hrt.shgraph.ShaderException;
import haxe.Timer;
using hxsl.Ast.Type;
using Lambda;

import hide.comp.SceneEditor;
import js.jquery.JQuery;
import h2d.col.Point;
import h2d.col.IPoint;
import hide.view.shadereditor.Box;
import hrt.shgraph.ShaderGraph;
import hrt.shgraph.ShaderNode;
import hide.view.GraphInterface;


typedef NodeInfo = { name : String, description : String, key : String };

typedef SavedClipboard = {
	nodes : Array<{
		pos : Point,
		nodeType : Class<ShaderNode>,
		props : Dynamic,
	}>,
	edges : Array<{ fromIdx : Int, fromOutputId : Int, toIdx : Int, toInputId : Int }>,
}

class PreviewShaderBase extends hxsl.Shader {
	static var SRC = {

		@input var input : {
			var position : Vec2;
		};

		@global var global : {
			var time : Float;
			var pixelSize : Vec2;
		};

		@global var camera : {
			var viewProj : Mat4;
			var position : Vec3;
		};

		var relativePosition : Vec3;
		var transformedPosition : Vec3;
		var projectedPosition : Vec4;
		var transformedNormal : Vec3;
		var fakeNormal : Vec3;
		var depth : Float;

		var particleRandom : Float;
        var particleLifeTime : Float;
        var particleLife : Float;

		function __init__() {
			depth = 0.0;
			relativePosition = vec3(input.position, 0.0);
			transformedPosition = vec3(input.position, 0.0);
			projectedPosition = vec4(input.position, 0.0, 0.0);
			fakeNormal = vec3(0,0,-1);
			transformedNormal = vec3(0,0,-1);
			particleLife = mod(global.time, 1.0);
			particleLifeTime = 1.0;
			particleRandom = hash12(vec2(floor(global.time)));
		}

		function hash12(p: Vec2) : Float
			{
				p = sign(p)*(floor(abs(p))+floor(fract(abs(p))*1000.0)/1000.0);
				var p3  = fract(vec3(p.xyx) * .1031);
				p3 += dot(p3, p3.yzx + 33.33);
				return fract((p3.x + p3.y) * p3.z);
			}
	}
}

typedef ClassRepoEntry =
{
	/**
		Class of the node
	**/
	cl: Class<ShaderNode>,

	/**
		Group where the node is in the search
	**/
	group: String,

	/**
		Displayed name in the seach box
	**/
	nameSearch: String,

	/**
		Description of the node in the search box
	**/
	description: String,

	/**
		Custom name for the node that will be created
	**/
	?nameOverride: String,

	/**
		Arguments passed to the constructor when the node is created
	**/
	args: Array<Dynamic>
};

class PreviewSettings {
	public var meshPath : String = "Sphere";
	public var alphaBlend: Bool = false;
	public var backfaceCulling : Bool = true;
	public var unlit : Bool = false;
	public function new() {};
}
class ShaderEditor extends hide.view.FileView implements GraphInterface.IGraphEditor {
	var graphEditor : hide.view.GraphEditor;
	var shaderGraph : hrt.shgraph.ShaderGraph;
	var currentGraph : hrt.shgraph.ShaderGraph.Graph;

	var compiledShader : hrt.prefab.Cache.ShaderDef;
	var previewShaderBase : PreviewShaderBase;
	var previewVar : hxsl.Ast.TVar;
	var needRecompile : Bool = true;

	var meshPreviewScene : hide.comp.Scene;
	var meshPreviewMeshes : Array<h3d.scene.Mesh> = [];
	var meshPreviewRoot3d : h3d.scene.Object;
	var meshShader : hxsl.DynamicShader;
	var meshPreviewCameraController : h3d.scene.CameraController;
	var previewSettings : PreviewSettings;
	var meshPreviewPrefab : hrt.prefab.Prefab;
	var meshPreviewprefabWatch : hide.tools.FileWatcher.FileWatchEvent;

	var parametersList : JQuery;
	var draggedParamId : Int;
	

	var defaultLight : hrt.prefab.Light;

	var queueReloadMesh = false;
	
	override function onDisplay() {
		super.onDisplay();
		element.html("");
		loadSettings();
		element.addClass("shader-editor");
 		shaderGraph = cast hide.Ide.inst.loadPrefab(state.path, null,  true);
		currentGraph = shaderGraph.getGraph(Fragment);
		previewShaderBase = new PreviewShaderBase();

		if (graphEditor != null)
			graphEditor.remove();
		graphEditor = new hide.view.GraphEditor(config, this, this.element);
		graphEditor.onDisplay();

		graphEditor.element.on("drop" ,function(e) {
			var posCursor = new Point(graphEditor.lX(ide.mouseX - 25), graphEditor.lY(ide.mouseY - 10));
			var inst = new ShaderParam();
			@:privateAccess var id = currentGraph.current_node_id++;
			inst.id = id;
			inst.parameterId = draggedParamId;
			inst.variable = shaderGraph.getParameter(inst.parameterId).variable;

			graphEditor.opBox(inst, true, graphEditor.currentUndoBuffer);
			graphEditor.commitUndo();
			// var node = Std.downcast(currentGraph.addNode(posCursor.x, posCursor.y, ShaderParam, []), ShaderParam);
			// node.parameterId = draggedParamId;
			// var paramShader = shaderGraph.getParameter(draggedParamId);
			// node.variable = paramShader.variable;
			// node.setName(paramShader.name);
			//setDisplayValue(node, paramShader.type, paramShader.defaultValue);
			//addBox(posCursor, ShaderParam, node);
		});

		var rightPannel = new Element(
			'<div id="rightPanel">
				<span>Parameters</span>
				<div class="tab expand" name="Scene" icon="sitemap">
					<div class="hide-block" >
						<div id="parametersList" class="hide-scene-tree hide-list">
						</div>
					</div>
					<div class="options-block hide-block">
						<input id="createParameter" type="button" value="Add parameter" />
						<select id="domainSelection"></select>
						<input id="launchCompileShader" type="button" value="Compile shader" />

						<input id="saveShader" type="button" value="Save" />
						<div>
							<input id="changeModel" type="button" value="Change Model" />
							<input id="removeModel" type="button" value="Remove Model" />
						</div>
						<input id="centerView" type="button" value="Center Graph" />
						<div>
							Display Compiled
							<input id="displayHxsl" type="button" value="Hxsl" />
							<input id="displayGlsl" type="button" value="Glsl" />
							<input id="displayHlsl" type="button" value="Hlsl" />
							<input id="display2" type="button" value="2" />
						</div>
						<input id="togglelight" type="button" value="Toggle Default Lights" />
						<input id="refreshGraph" type="button" value="Refresh Shader Graph" />
					</div>
				</div>
			</div>'
		);

		rightPannel.appendTo(element);

		var newParamCtxMenu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{ label : "Number", click : () -> createParameter(TFloat) },
			{ label : "Vec2", click : () -> createParameter(TVec(2, VFloat)) },
			{ label : "Vec3", click : () -> createParameter(TVec(3, VFloat)) },
			{ label : "Color", click : () -> createParameter(TVec(4, VFloat)) },
			{ label : "Texture", click : () -> createParameter(TSampler(T2D,false)) },
		];

		rightPannel.find("#createParameter").on("click", function() {
			new hide.comp.ContextMenu(newParamCtxMenu);
		});

		parametersList = rightPannel.find("#parametersList");
		parametersList.on("contextmenu", function(e) {
			e.preventDefault();
			e.stopPropagation();
			new hide.comp.ContextMenu([
				{
					label : "Add Parameter",
					menu : newParamCtxMenu,
				},
			]);
		});

		for (k in shaderGraph.parametersKeys) {
			var pElt = addParameter(shaderGraph.parametersAvailable.get(k), shaderGraph.parametersAvailable.get(k).defaultValue);
		}

		rightPannel.find("#display2").click((e) -> {
			trace(hxsl.Printer.shaderToString(shaderGraph.compile(Fragment).shader.data, true));
		});


		graphEditor.onPreviewUpdate = onPreviewUpdate;
		graphEditor.onNodePreviewUpdate = onNodePreviewUpdate;

		initMeshPreview();
	}

	function createParameter(type : Type) {
		//beforeChange();
		var paramShaderID = shaderGraph.addParameter(type);
		//afterChange();
		var paramShader = shaderGraph.getParameter(paramShaderID);

		var elt = addParameter(paramShader, null);
		//updateParam(paramShaderID);

		elt.find(".input-title").focus();
	}

	function moveParameter(parameter : Parameter, up : Bool) {
		var parameterElt = parametersList.find("#param_" + parameter.id);
		var parameterPrev = shaderGraph.parametersAvailable.get(shaderGraph.parametersKeys[shaderGraph.parametersKeys.indexOf(parameter.id) + (up? -1 : 1)]);
		var parameterPrevElt = parametersList.find("#param_" + parameterPrev.id);
		if (up)
			parameterElt.insertBefore(parameterPrevElt);
		else
			parameterElt.insertAfter(parameterPrevElt);
		shaderGraph.parametersKeys.remove(parameter.id);
		shaderGraph.parametersKeys.insert(shaderGraph.parametersKeys.indexOf(parameterPrev.id) + (up? 0 : 1), parameter.id);
		shaderGraph.checkParameterIndex();
	}

	// function updateParam(id : Int) {
	// 	var param = shaderGraph.getParameter(id);
	// 	setParamValueByName(currentShader, param.name, param.defaultValue);
	// 	//previewParamDirty = true;
	// }

	function addParameter(parameter : Parameter, ?value : Dynamic) {

		var elt = new Element('<div id="param_${parameter.id}" class="parameter" draggable="true" ></div>').appendTo(parametersList);
		elt.on("click", function(e) {e.stopPropagation();});
		elt.on("contextmenu", function(e) {
			var elements = [];
			e.stopPropagation();
			var newCtxMenu : Array<hide.comp.ContextMenu.ContextMenuItem> = [
				{ label : "Move up", click : () -> {
					//beforeChange();
					moveParameter(parameter, true);
					//afterChange();
				}, enabled: shaderGraph.parametersKeys.indexOf(parameter.id) > 0},
				{ label : "Move down", click : () -> {
					//beforeChange();
					moveParameter(parameter, false);
					//afterChange();
				}, enabled: shaderGraph.parametersKeys.indexOf(parameter.id) < shaderGraph.parametersKeys.length-1}
			];
			new hide.comp.ContextMenu(newCtxMenu);
			e.preventDefault();

		});
		var content = new Element('<div class="content" ></div>');
		content.hide();
		var defaultValue = new Element("<div><span>Default: </span></div>").appendTo(content);

		var typeName = "";
		switch(parameter.type) {
			case TFloat:
				var parentRange = new Element('<input type="range" min="-1" max="1" />').appendTo(defaultValue);
				var range = new hide.comp.Range(null, parentRange);
				var rangeInput = @:privateAccess range.f;
				rangeInput.on("mousedown", function(e) {
					elt.attr("draggable", "false");
					//beforeChange();
				});
				rangeInput.on("mouseup", function(e) {
					elt.attr("draggable", "true");
					//afterChange();
				});
				if (value == null) value = 0;
				range.value = value;
				shaderGraph.setParameterDefaultValue(parameter.id, value);
				range.onChange = function(moving) {
					if (!shaderGraph.setParameterDefaultValue(parameter.id, range.value))
						return;
					//setBoxesParam(parameter.id);
					//updateParam(parameter.id);
				};
				typeName = "Number";
			case TVec(4, VFloat):
				var parentPicker = new Element('<div style="width: 35px; height: 25px; display: inline-block;"></div>').appendTo(defaultValue);
				var picker = new hide.comp.ColorPicker.ColorBox(null, parentPicker, true, true);


				if (value == null)
					value = [0, 0, 0, 1];
				var start : h3d.Vector = h3d.Vector.fromArray(value);
				shaderGraph.setParameterDefaultValue(parameter.id, value);
				picker.value = start.toColor();
				picker.onChange = function(move) {
					var vecColor = h3d.Vector4.fromColor(picker.value);
					if (!shaderGraph.setParameterDefaultValue(parameter.id, [vecColor.x, vecColor.y, vecColor.z, vecColor.w]))
						return;
					//setBoxesParam(parameter.id);
					//updateParam(parameter.id);
				};
			case TVec(n, VFloat):
				if (value == null)
					value = [for (i in 0...n) 0.0];

				shaderGraph.setParameterDefaultValue(parameter.id, value);
				//var row = new Element('<div class="flex"/>').appendTo(defaultValue);

				for( i in 0...n ) {
					var parentRange = new Element('<input type="range" min="-1" max="1" />').appendTo(defaultValue);
					var range = new hide.comp.Range(null, parentRange);
					range.value = value[i];

					var rangeInput = @:privateAccess range.f;
					rangeInput.on("mousedown", function(e) {
						elt.attr("draggable", "false");
						//beforeChange();
					});
					rangeInput.on("mouseup", function(e) {
						elt.attr("draggable", "true");
						//afterChange();
					});

					range.onChange = function(move) {
						value[i] = range.value;
						if (!shaderGraph.setParameterDefaultValue(parameter.id, value))
							return;
						//setBoxesParam(parameter.id);
						//updateParam(parameter.id);
					};
					//if(min == null) min = isColor ? 0.0 : -1.0;
					//if(max == null)	max = 1.0;
					//e.attr("min", "" + min);
					//e.attr("max", "" + max);
				}
				typeName = "Vec" + n;
			case TSampler(_):
				var parentSampler = new Element('<input type="texturepath" field="sampler2d"/>').appendTo(defaultValue);

				var tselect = new hide.comp.TextureChoice(null, parentSampler);
				tselect.value = value;
				tselect.onChange = function(undo: Bool) {
					//beforeChange();
					if (!shaderGraph.setParameterDefaultValue(parameter.id, tselect.value))
						return;
					//afterChange();
					//setBoxesParam(parameter.id);
					//updateParam(parameter.id);
				}
				typeName = "Texture";

			default:
		}

		var header = new Element('<div class="header">
									<div class="title">
										<i class="ico ico-chevron-right" ></i>
										<input class="input-title" type="input" value="${parameter.name}" />
									</div>
									<div class="type">
										<span>${typeName}</span>
									</div>
								</div>');

		var internal = new Element('<div><input type="checkbox" name="internal" id="internal"></input><label for="internal">Internal</label><div>').appendTo(content).find("#internal");
		internal.prop("checked", parameter.internal ?? false);

		internal.on('change', function(e) {
			//beforeChange();
			parameter.internal = internal.prop("checked");
			//afterChange();
		});

		var perInstanceCb = new Element('<div><input type="checkbox" name="perinstance"/><label for="perinstance">Per instance</label><div>');
		var shaderParams : Array<ShaderParam> = [];
		// for (b in listOfBoxes) {
		// 	var tmpShaderParam = Std.downcast(b.getInstance(), ShaderParam);
		// 	if (tmpShaderParam != null && tmpShaderParam.parameterId == parameter.id) {
		// 		shaderParams.push(tmpShaderParam);
		// 		break;
		// 	}
		// }

		var checkbox = perInstanceCb.find("input");
		if (shaderParams.length > 0)
			checkbox.prop("checked", shaderParams[0].perInstance);
		checkbox.on("change", function() {
			//beforeChange();
			var checked : Bool = checkbox.prop("checked");
			for (shaderParam in shaderParams)
				shaderParam.perInstance = checked;
			//afterChange();
			requestRecompile();
		});
		perInstanceCb.appendTo(content);

		header.appendTo(elt);
		content.appendTo(elt);
		var actionBtns = new Element('<div class="action-btns" ></div>').appendTo(content);
		var deleteBtn = new Element('<input type="button" value="Delete" />');
		/*deleteBtn.on("click", function() {
			for (b in listOfBoxes) {
				var shaderParam = Std.downcast(b.getInstance(), ShaderParam);
				if (shaderParam != null && shaderParam.parameterId == parameter.id) {
					error("This parameter is used in the graph.");
					return;
				}
			}
			beforeChange();
			shaderGraph.removeParameter(parameter.id);
			afterChange();
			elt.remove();
		});*/
		deleteBtn.appendTo(actionBtns);



		var inputTitle = elt.find(".input-title");
		inputTitle.on("click", function(e) {
			e.stopPropagation();
		});
		inputTitle.on("keydown", function(e) {
			e.stopPropagation();
		});
		inputTitle.on("change", function(e) {
			var newName = inputTitle.val();
			// if (shaderGraph.setParameterTitle(parameter.id, newName)) {
			// 	for (b in listOfBoxes) {
			// 		var shaderParam = Std.downcast(b.getInstance(), ShaderParam);
			// 		if (shaderParam != null && shaderParam.parameterId == parameter.id) {
			// 			beforeChange();
			// 			shaderParam.setName(newName);
			// 			afterChange();
			// 		}
			// 	}
			// }
		});
		inputTitle.on("focus", function() { inputTitle.select(); } );

		// elt.find(".header").on("click", function() {
		// 	toggleParameter(elt);
		// });

		elt.on("dragstart", function(e) {
			draggedParamId = parameter.id;
		});

		inline function isAfter(e) {
			return e.clientY > (elt.offset().top + elt.outerHeight() / 2.0);
		}

		elt.on("dragover", function(e : js.jquery.Event) {
			var after = isAfter(e);
			elt.toggleClass("hovertop", !after);
			elt.toggleClass("hoverbot", after);
			e.preventDefault();
		});

		elt.on("dragleave", function(e) {
			elt.toggleClass("hovertop", false);
			elt.toggleClass("hoverbot", false);
		});

		elt.on("dragenter", function(e) {
			e.preventDefault();
		});

		elt.on("drop", function(e) {
			elt.toggleClass("hovertop", false);
			elt.toggleClass("hoverbot", false);
			var other = shaderGraph.getParameter(draggedParamId);
			var after = isAfter(e);
			moveParameterTo(other, parameter, after);
		});

		return elt;
	}

	function moveParameterTo(paramA: Parameter, paramB: Parameter, after: Bool) {
		if (paramA == paramB)
			return;
		var aElt = parametersList.find("#param_" + paramA.id);
		var bElt = parametersList.find("#param_" + paramB.id);

		if (!after) {
			aElt.insertBefore(bElt);
		} else {
			aElt.insertAfter(bElt);
		}

		shaderGraph.parametersKeys.remove(paramA.id);
		shaderGraph.parametersKeys.insert(shaderGraph.parametersKeys.indexOf(paramB.id)+ (after ? 1 : 0) , paramA.id);

		shaderGraph.checkParameterIndex();
	}


	public function loadSettings() {
		var save = haxe.Json.parse(getDisplayState("previewSettings") ?? "{}");
		previewSettings = new PreviewSettings();
		for (f in Reflect.fields(previewSettings)) {
			var v = Reflect.field(save, f);
			if (v != null) {
				Reflect.setField(previewSettings, f, v);
			}
		}
	}

	public function saveSettings() {
		saveDisplayState("previewSettings", haxe.Json.stringify(previewSettings));
	}

	public function initMeshPreview() {
		if (meshPreviewScene != null) {
			meshPreviewScene.element.remove();
		}
		var container = new Element('<div id="preview"></div>').appendTo(graphEditor.element);
		meshPreviewScene = new hide.comp.Scene(config, null, container);
		meshPreviewScene.onReady = onMeshPreviewReady;
		meshPreviewScene.onUpdate = onMeshPreviewUpdate;

		var toolbar = new Element('<div class="hide-toolbar2"></div>').appendTo(container);
		var group = new Element('<div class="tb-group"></div>').appendTo(toolbar);
		var menu = new Element('<div class="button2 transparent" title="More options"><div class="ico ico-navicon"></div></div>');
		menu.appendTo(group);
		menu.click((e) -> {
			var menu = new hide.comp.ContextMenu([
				{label: "Reset Camera", click: resetPreviewCamera},
				{label: "", isSeparator: true},
				{label: "Sphere", click: setMeshPreviewSphere},
				{label: "Plane", click: setMeshPreviewPlane},
				{label: "Mesh ...", click: chooseMeshPreviewFBX},
				{label: "Prefab/FX ...", click: chooseMeshPreviewPrefab},
				{label: "", isSeparator: true},
				{label: "Render Settings", menu: [
					{label: "Alpha Blend", click: () -> {previewSettings.alphaBlend = !previewSettings.alphaBlend; applyShaderMesh(); saveSettings();}, stayOpen: true, checked: previewSettings.alphaBlend},
					{label: "Backface Cull", click: () -> {previewSettings.backfaceCulling = !previewSettings.backfaceCulling; applyShaderMesh(); saveSettings();}, stayOpen: true, checked: previewSettings.backfaceCulling},
					{label: "Unlit", click: () -> {previewSettings.unlit = !previewSettings.unlit; applyShaderMesh(); saveSettings();}, stayOpen: true, checked: previewSettings.unlit},
				], enabled: meshPreviewPrefab == null}
			]);
		});
	}

	public function onMeshPreviewUpdate(dt: Float) {
		if (queueReloadMesh) {
			queueReloadMesh = false;
			loadMeshPreviewFromString(previewSettings.meshPath);
		}
	}

	public function cleanupPreview() {
		if (meshPreviewPrefab != null) {
			meshPreviewPrefab.dispose();
			meshPreviewPrefab = null;
			if (meshPreviewprefabWatch != null) {
				Ide.inst.fileWatcher.unregister(meshPreviewprefabWatch.path, meshPreviewprefabWatch.fun);
				meshPreviewprefabWatch = null;
			}
		}
		for (mesh in meshPreviewMeshes)
			mesh.remove();

		meshPreviewRoot3d.removeChildren();
	}

	public function setMeshPreviewMesh(mesh: h3d.scene.Mesh) {
		cleanupPreview();

		meshPreviewRoot3d.addChild(mesh);
		meshPreviewMeshes.resize(0);
		meshPreviewMeshes.push(mesh);

		applyShaderMesh();
		resetPreviewCamera();
	}

	public function setMeshPreviewSphere() {
		previewSettings.meshPath = "Sphere";
		saveSettings();

		var sp = new h3d.prim.Sphere(1, 128, 128);
		sp.addNormals();
		sp.addUVs();
		sp.addTangents();
		setMeshPreviewMesh(new h3d.scene.Mesh(sp));
	}

	public function setMeshPreviewPlane() {
		previewSettings.meshPath = "Plane";
		saveSettings();

		var plane = hrt.prefab.l3d.Polygon.createPrimitive(Quad(4));
		var m = new h3d.scene.Mesh(plane);
		m.setScale(2.0);
		m.material.mainPass.culling = None;
		setMeshPreviewMesh(m);
	}

	public function chooseMeshPreviewFBX() {
		var basedir = haxe.io.Path.directory(previewSettings.meshPath);
		if (basedir == "" || !haxe.io.Path.isAbsolute(basedir)) {
			haxe.io.Path.join([Ide.inst.resourceDir, basedir]);
		}
		trace(basedir);
		Ide.inst.chooseFile(["fbx"], (path : String) -> {
			if (path == null)
				return;
			setMeshPreviewFBX(path);
		}, false, basedir);
	}

	public function chooseMeshPreviewPrefab() {
		var basedir = haxe.io.Path.directory(previewSettings.meshPath);
		if (basedir == "" || !haxe.io.Path.isAbsolute(basedir)) {
			haxe.io.Path.join([Ide.inst.resourceDir, basedir]);
		}
		trace(basedir);
		Ide.inst.chooseFile(["prefab", "fx"], (path : String) -> {
			if (path == null)
				return;
			setMeshPreviewPrefab(path);
		}, false, basedir);
	}

	public function resetPreviewCamera() {
		var bounds = new h3d.col.Bounds();
		for (mesh in meshPreviewMeshes) {
			var b = mesh.getBounds();
			bounds.add(b);
		}
		var sp = bounds.toSphere();
		meshPreviewCameraController.set(sp.r * 3.0, Math.PI / 4, Math.PI * 5 / 13, sp.getCenter());
	}

	public function loadMeshPreviewFromString(str: String) {
		switch (str){
			case "Sphere":
				setMeshPreviewSphere();
			case "Plane":
				setMeshPreviewPlane();
			default: {
				if (StringTools.endsWith(str, ".fbx")) {
					setMeshPreviewFBX(str);
				}
				else if (StringTools.endsWith(str, ".fx") || StringTools.endsWith(str, ".prefab")) {
					setMeshPreviewPrefab(str);
				}
				else {
					setMeshPreviewSphere();
				}
			}
		}
	}

	public function setMeshPreviewFBX(str: String) {
		var model : h3d.scene.Mesh = null;
		try {
			model = Std.downcast(meshPreviewScene.loadModel(str, false, true), h3d.scene.Mesh);
		} catch (e) {
			Ide.inst.quickError('Could not load mesh $str, error : $e');
			setMeshPreviewSphere();
			return;
		}

		setMeshPreviewMesh(model);
		previewSettings.meshPath = str;
		saveSettings();
	}

	public function setMeshPreviewPrefab(str: String) {
		cleanupPreview();
		
		try {
			meshPreviewPrefab = Ide.inst.loadPrefab(str);
		} catch (e) {
			Ide.inst.quickError('Could not load mesh $str, error : $e');
			setMeshPreviewSphere();
			return;
		}


		meshPreviewPrefab.setSharedRec(new hide.prefab.ContextShared(null, meshPreviewRoot3d));
		meshPreviewPrefab.make();
		meshPreviewMeshes.resize(0);

		var meshes = meshPreviewRoot3d.findAll((f) -> Std.downcast(f, h3d.scene.Mesh));
		for (mesh in meshes) {
			var mats = mesh.getMaterials();
			for (mat in mats) {
				for (shader in mat.mainPass.getShaders()) {
					var dyn = Std.downcast(shader, DynamicShader);
					if (dyn != null) {
						@:privateAccess
						if (dyn.shader.data.name == this.state.path) {
							meshPreviewMeshes.push(mesh);
							break;
						}
					}
				}
			}
		}

		if (meshPreviewMeshes.length <= 0) {
			Ide.inst.quickError('Prefab/FX $str does not contains this shadergraph');
			setMeshPreviewSphere();
			return;
		}

		meshPreviewprefabWatch = Ide.inst.fileWatcher.register(str, () -> queueReloadMesh = true, false);

		applyShaderMesh();
		resetPreviewCamera();
		previewSettings.meshPath = str;
		saveSettings();
	}

	public function onMeshPreviewReady() {
		if (meshPreviewScene.s3d == null)
			throw "meshPreviewScene not ready";

		var moved = false;
		meshPreviewCameraController = new h3d.scene.CameraController(meshPreviewScene.s3d);
		meshPreviewCameraController.loadFromCamera(false);
		meshPreviewRoot3d = new h3d.scene.Object(meshPreviewScene.s3d);
		loadMeshPreviewFromString(previewSettings.meshPath);
	}

	public function replaceMeshShader(mesh: h3d.scene.Mesh, newShader: hxsl.DynamicShader) {
		if (newShader == null)
			return;

		@:privateAccess
		for (m in mesh.getMaterials()) {
			var found = false;

			var curShaderList = m.mainPass.shaders;
			while (curShaderList != null && curShaderList != m.mainPass.parentShaders) {
				var dyn = Std.downcast(curShaderList.s, hxsl.DynamicShader);
				
				@:privateAccess
				if (dyn != null) {
					if (dyn.shader.data.name == newShader.shader.data.name) {
						found = true;
						curShaderList.s = newShader;
						m.mainPass.resetRendererFlags();
						m.mainPass.selfShadersChanged = true;						
					}
				}

				// Only override renderer settings if we are not previewing a prefab
				// (because prefabs can have their own material settings)
				if (meshPreviewPrefab == null) {
					m.blendMode = previewSettings.alphaBlend ? Alpha : None;
					m.mainPass.culling = previewSettings.backfaceCulling ? Back : None;
					if (previewSettings.unlit) {
						m.mainPass.setPassName("afterTonemapping");
						m.shadows = false;
					}
					else {
						m.mainPass.setPassName("default");
						m.shadows = true;
					}
				}

				curShaderList = curShaderList.next;
			}

			if (!found) {
				m.mainPass.addShader(newShader);
			}
		}
	}

	public function applyShaderMesh() {
		for (m in meshPreviewMeshes) {
			replaceMeshShader(m, meshShader);
		}
	}


	public function onPreviewUpdate() {
		if (needRecompile) {
			compileShader();
		}

		@:privateAccess
		{
			var engine = graphEditor.previewsScene.engine;
			var t = engine.getCurrentTarget();
			graphEditor.previewsScene.s2d.ctx.globals.set("global.pixelSize", new h3d.Vector(2 / (t == null ? engine.width : t.width), 2 / (t == null ? engine.height : t.height)));	
		}

		@:privateAccess
		if (meshPreviewScene.s3d != null) {
			meshPreviewScene.s3d.renderer.ctx.time = graphEditor.previewsScene.s3d.renderer.ctx.time;
		}

		return true;
	}
	var bitmapToShader : Map<h2d.Bitmap, hxsl.DynamicShader> = [];
	public function onNodePreviewUpdate(node: IGraphNode, bitmap: h2d.Bitmap) {
		if (compiledShader == null) {
			bitmap.visible = false;
			return;
		}
		var shader = bitmapToShader.get(bitmap);
		if (shader == null) {
			for (s in bitmap.getShaders()) {
				bitmap.removeShader(s);
			}
			shader = new DynamicShader(compiledShader.shader);
			bitmapToShader.set(bitmap, shader);
			bitmap.addShader(previewShaderBase);
			bitmap.addShader(shader);
		}
		for (init in compiledShader.inits) {
			if (init.variable == previewVar)
				setParamValue(shader, previewVar, node.getId() + 1);
			else
				setParamValue(shader, init.variable, init.value);
		}
	}

	function setParamValue(shader : DynamicShader, variable : hxsl.Ast.TVar, value : Dynamic) {
		@:privateAccess ShaderGraph.setParamValue(shader, variable, value);
	}

	/** IGraphEditor interface **/
	public function getNodes() : Iterator<IGraphNode> {
		return currentGraph.getNodes().iterator();
	}

	public function getEdges() : Iterator<Edge> {
		var edges : Array<Edge> = [];
		for (id => node in currentGraph.getNodes()) {
			for (inputId => connection in node.connections) {
				if (connection != null) {
					edges.push(
						{
							nodeFromId: connection.from.getId(),
							outputFromId: connection.outputId,
							nodeToId: id,
							inputToId: inputId,
						});
				}
			}
		}
		return edges.iterator();
	}

	public function getAddNodesMenu() : Array<AddNodeMenuEntry> {
		var entries : Array<AddNodeMenuEntry> = [];

		var id = 0;
		for (i => node in ShaderNode.registeredNodes) {
			var metas = haxe.rtti.Meta.getType(node);
			if (metas.group == null) {
				continue;
			}

			var group = metas.group != null ? metas.group[0] : "Other";
			var name = metas.name != null ? metas.name[0] : "unknown";
			var description = metas.description != null ? metas.description[0] : "";

			entries.push(
				{
					name: name,
					group: group,
					description: description,
					onConstructNode: () -> {
						@:privateAccess var id = currentGraph.current_node_id++;
						var inst = std.Type.createInstance(node, []);
						inst.setId(id);
						return inst;
					},
				}
			);

			var aliases = std.Type.createEmptyInstance(node).getAliases(name, group, description) ?? [];
			for (alias in aliases) {
				entries.push(
					{
						name: alias.nameSearch ?? alias.nameOverride ?? name,
						group: alias.group ?? group,
						description: alias.description ?? description,
						onConstructNode: () -> {
							@:privateAccess var id = currentGraph.current_node_id++;
							var inst = std.Type.createInstance(node, alias.args ?? []);
							inst.setId(id);
							return inst;
						},
					}
				);
			}
		}
		return entries;
	}

	public function addNode(node: IGraphNode) : Void {
		currentGraph.addNode(cast node);
		requestRecompile();
	}

	public function removeNode(id: Int) : Void {
		currentGraph.removeNode(id);
		requestRecompile();
	}

	public function canAddEdge(edge: Edge) : Bool {
		return currentGraph.canAddEdge({outputNodeId: edge.nodeFromId, outputId: edge.outputFromId, inputNodeId: edge.nodeToId, inputId: edge.inputToId});
	}

	public function addEdge(edge: Edge) : Void {
		var input = currentGraph.getNode(edge.nodeToId);
		input.connections[edge.inputToId] = {from: currentGraph.getNode(edge.nodeFromId), outputId: edge.outputFromId};
		requestRecompile();
	}

	public function removeEdge(nodeToId: Int, inputToId: Int) : Void {
		var input = currentGraph.getNode(nodeToId);
		input.connections[inputToId] = null;
		requestRecompile();
	}

	public override function save() {
		var content = shaderGraph.saveToText();
		currentSign = ide.makeSignature(content);
		sys.io.File.saveContent(getPath(), content);
		super.save();
	}

	public function getUndo() : hide.ui.UndoHistory {
		return undo;
	}

	override function getDefaultContent() {
		var p = (new hrt.shgraph.ShaderGraph(null, null)).serialize();
		return haxe.io.Bytes.ofString(ide.toJSON(p));
	}

	public function requestRecompile() {
		needRecompile = true;
	}

	public function compileShader() {
		needRecompile = false;
		try {
			var start = Timer.stamp();
			compiledShader = shaderGraph.compile(Fragment);
			bitmapToShader.clear();
			previewVar = compiledShader.inits.find((e) -> e.variable.name == hrt.shgraph.Variables.previewSelectName).variable;
			var end = Timer.stamp();
			Ide.inst.quickMessage('shader recompiled in ${(end - start) * 1000.0} ms', 2.0);

			meshShader = new hxsl.DynamicShader(compiledShader.shader);
			for (init in compiledShader.inits) {
				if (init.variable == previewVar)
					setParamValue(meshShader, previewVar, 0);
				else
					setParamValue(meshShader, init.variable, init.value);
			}

			applyShaderMesh();
		} catch (err) {
			Ide.inst.quickError(err);
		}
	}
	
	static var _ = FileTree.registerExtension(ShaderEditor,["shgraph"],{ icon : "scribd", createNew: "Shader Graph" });
}