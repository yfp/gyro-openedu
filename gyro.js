var Gyro = (function() {

    var width = 400, height = 400;
    var container, renderer, scene, camera, projector,
        ambientlight, directionalLight,
        cylinder, cube, nonSelectedMaterial, selectedMaterial;
    // Revolutions per second
    var angularSpeed = 0, lastTime = 0;
    var state = {
            'selectedObjects': {
                'cylinder': false,
                'cube': false
            }
        },
        channel;

    // Establish a channel only if this application is embedded in an iframe.
    // This will let the parent window communicate with this application using
    // RPC and bypass SOP restrictions.
    if (window.parent !== window) {
        channel = Channel.build({
            window: window.parent,
            origin: "*",
            scope: "JSInput"
        });

        channel.bind("getGrade", getGrade);
        channel.bind("getState", getState);
        channel.bind("setState", setState);
    }

    function init() {
        container = document.getElementById('container');
        // Renderer
        // First check if WebGL is supported. If not, rely on the canvas
        // render and use a scene with less triangles as it is slow.
        var testCanvas = document.createElement("canvas");
        var webglContext = null;
        var contextNames = ["experimental-webgl", "webgl", "moz-webgl",
                            "webkit-3d"];
        var radiusSegments, heightSegments;
        for (var i = 0; i < contextNames.length; i++) {
            try {
                webglContext = testCanvas.getContext(contextNames[i]);
                if (webglContext) {
                    break;
                }
            }
            catch (e) {
            }
        }

        if (webglContext) {
            renderer = new THREE.WebGLRenderer({antialias:true});
            radiusSegments = 50;
            heightSegments = 50;
        }
        else {
            renderer = new THREE.CanvasRenderer();
            radiusSegments = 10;
            heightSegments = 10;
        }

        renderer.setSize(width, height);
        renderer.setClearColor(0xFFFFFF, 1);
        container.appendChild(renderer.domElement);

        // Scene
        scene = new THREE.Scene();

        // Camera
        camera = new THREE.PerspectiveCamera(45, width/height, 1, 1000);
        camera.position.x = 400;
        camera.position.y = 400;
        camera.position.z = 200;
        camera.up.set( 0, 0, 1 );
        camera.lookAt(new THREE.Vector3(0,0,0));
        camera.updateProjectionMatrix();

        // Materials
        unselectedMaterial = new THREE.MeshPhongMaterial({
            specular: '#a9fcff',
            color: '#00abb1',
            emissive: '#006063',
            shininess: 100
        });

        selectedMaterial = new THREE.MeshPhongMaterial({
            specular: '#a9fcff',
            color: '#abb100',
            emissive: '#606300',
            shininess: 100
        });

        if (!webglContext) {
            unselectedMaterial.overdraw = 1.0;
            selectedMaterial.overdraw = 1.0;
        }

        // Cube
        cube = new THREE.Mesh(new THREE.CubeGeometry(100, 150, 200),
                                                    unselectedMaterial);
        cube.position.x = 0;
        cube.overdraw = true;
        // cube.omega = new THREE.Vector3(0,0,0.1);
        cube.quaternion.setFromAxisAngle(new THREE.Vector3(1,1,1), Math.PI/3 )
        scene.add(cube);

        // Ambient light
        ambientLight = new THREE.AmbientLight(0x222222);
        scene.add(ambientLight);

        // Directional light
        directionalLight = new THREE.DirectionalLight(0xffffff);
        directionalLight.position.set(1, 1, 1).normalize();
        scene.add(directionalLight);

        // Used to select element with mouse click
        projector = new THREE.Projector();

        renderer.domElement.addEventListener('click', onMouseClick, false);

        // Start animation
        animate();
    }

    // This function is executed on each animation frame
    function animate() {
        // Request new frame
        requestAnimationFrame(animate);
        render();
    }

    function render() {
        // Update
        var time = (new Date()).getTime(),
            timeDiff = time - lastTime,
            angleChange = angularSpeed * timeDiff * 2 * Math.PI / 1000;
        cube.rotation.z += angleChange;
        lastTime = time;

        // Render
        renderer.render(scene, camera);
    }

    function onMouseClick(event) {
        var vector, raycaster, intersects;

        vector = new THREE.Vector3((event.clientX / width) * 2 - 1,
                                -(event.clientY / height) * 2 + 1, 1);
        projector.unprojectVector(vector, camera);
        raycaster = new THREE.Raycaster(camera.position,
                                        vector.sub(camera.position).normalize());
        intersects = raycaster.intersectObjects(scene.children);

        if (intersects.length > 0) {
            if (intersects[0].object === cube) {
                state.selectedObjects.cube = !state.selectedObjects.cube;
                if(angularSpeed > 0)
                    angularSpeed = 0;
                else angularSpeed = 0.5;
            }
            updateMaterials();
        }
    }

    function updateMaterials() {
        if (state.selectedObjects.cube) {
            cube.material =  selectedMaterial;
        }
        else {
            cube.material =  unselectedMaterial;
        }
    }

    init();

    function getGrade() {
        // The following return value may or may not be used to grade
        // server-side.
        // If getState and setState are used, then the Python grader also gets
        // access to the return value of getState and can choose it instead to
        // grade.
        return JSON.stringify(state['selectedObjects']);
    }

    function getState() {
        return JSON.stringify(state);
    }

    // This function will be called with 1 argument when JSChannel is not used,
    // 2 otherwise. In the latter case, the first argument is a transaction
    // object that will not be used here
    // (see http://mozilla.github.io/jschannel/docs/)
    function setState() {
        stateStr = arguments.length === 1 ? arguments[0] : arguments[1];
        state = JSON.parse(stateStr);
        updateMaterials();
    }

    return {
        getState: getState,
        setState: setState,
        getGrade: getGrade
    };
}());