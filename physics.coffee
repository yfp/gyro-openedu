THREE.Quaternion.prototype.addQuaternion = (q, b=1)->
  new THREE.Quaternion(
    @.x+q.x * b
    @.y+q.y * b
    @.z+q.z * b
    @.w+q.w * b
  )

THREE.Vector3.prototype.addVector3 = (v, b=1)->
  new THREE.Vector3(
    @.x+v.x * b
    @.y+v.y * b
    @.z+v.z * b
  )

lsum = (vec1, vec2, k1=1) ->
  vec1.map (e, i) -> vec1[i]*k1 + vec2[i]

stepRungeKutta = (vec, func, t, dt) ->
  k1 = func( t,      vec                )
  k2 = func( t+dt/2, lsum(k1, vec, dt/2) )
  k3 = func( t+dt/2, lsum(k2, vec, dt/2) )
  k4 = func( t+dt,   lsum(k3, vec, dt)   )

  vec.map (e, i) ->
    e + dt*((k1[i]+k4[i])/6 + (k2[i]+k3[i])/3)

Gyro = do ->
  $(()->
    pi = Math.PI
    degree = pi/180
    width = 400
    height = 300
    container = undefined
    renderer = undefined
    scene = undefined
    camera = undefined
    raycaster = new THREE.Raycaster()
    ambientlight = undefined
    directionalLight = undefined
    cylinder = undefined
    cube = undefined
    unselectedMaterial = undefined
    selectedMaterial = undefined
    controls = undefined
    model = undefined
    line = undefined
    startTime = (new Date).getTime()
    plot = undefined
    nutData = []
    plotData = {
      theta:
        data: [ [0,0] ]
        label: "theta"
        color: 1
      psi:
        data: [ [0,0] ]
        label: "psi"
        color: 0
      # q:
      #   data: [ [0,0] ]
      #   label: "q"
      #   color: 2
    }
    MAX_POINTS = 5000

    simulationState = off
    rotationVelocity = {
      precession: 30
      nutation: 0
      rotation: 400
    }

    omega = new THREE.Vector3(0, 0, 5)
    weight = 10

    gyroGeometry = {
      angle: 36*degree
      length: 150
      centerMass: 113.8
      cubesSize: 30
    }

    precession = {id: 'precession', value: 0}
    nutation   = {id: 'nutation', value: 0}
    rotation   = {id: 'rotation', value: 0}
    precessionDot = {id: 'precession', value: 0}
    nutationDot   = {id: 'nutation', value: 0}
    rotationDot   = {id: 'rotation', value: 3.0}

    max_nutation = 72*degree

    J = {
      A: 7
      B: 7
      C: 10
    }
    J.CB = J.C - J.B
    J.BA = J.B - J.A
    J.AC = J.A - J.C


    # Revolutions per second
    angularSpeed = 0
    lastTime = 0
    state = 'selectedObjects':
      'cylinder': false
      'cube': false
    channel = undefined
    # Establish a channel only if this application is embedded in an iframe.
    # This will let the parent window communicate with this application using
    # RPC and bypass SOP restrictions.

    updateInitialConditions = () ->
      [sin,cos] = [Math.sin, Math.cos]
      psi   = precession.value*degree
      theta = nutation.value*degree
      phi   = rotation.value*degree
      
      psid   = precessionDot.value
      thetad = nutationDot.value
      phid   = rotationDot.value

      omega.x = psid * sin(theta)*sin(phi) + thetad * cos(phi)
      omega.y = psid * sin(theta)*cos(phi) - thetad * sin(phi)
      omega.z = psid * cos(theta) + phid

      # console.log "updated", omega

      q = new THREE.Quaternion()
      qaa = (x, y, z, a) ->
        new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(x,y,z), a )
      q.multiply qaa(0,0,1, psi)
      q.multiply qaa(1,0,0, theta)
      q.multiply qaa(0,0,1, phi)
      model.quaternion.copy q
      model.position.z = Math.cos(theta) * gyroGeometry.centerMass

    stopSimulation = () ->
      simulationState = off
      $(".play.on").toggleClass "on"

    init = ->
      container = document.getElementById('container')
      testCanvas = document.createElement('canvas')
      webglContext = null
      contextNames = [
        'experimental-webgl'
        'webgl'
        'moz-webgl'
        'webkit-3d'
      ]
      radiusSegments = undefined
      heightSegments = undefined
      i = 0
      while i < contextNames.length
        try
          webglContext = testCanvas.getContext(contextNames[i])
          if webglContext
            break
        catch e
        i++
      if webglContext
        renderer = new (THREE.WebGLRenderer)(antialias: true)
        radiusSegments = 50
        heightSegments = 50
      else
        renderer = new (THREE.CanvasRenderer)
        radiusSegments = 10
        heightSegments = 10
      renderer.setSize width, height
      renderer.setClearColor 0xFFFFFF, 1
      container.appendChild renderer.domElement
      # Scene
      scene = new (THREE.Scene)
      # Camera
      camera = new (THREE.PerspectiveCamera)(45, width / height, 1, 1000)
      camera.position.x = 400
      camera.position.y = 400
      camera.position.z = 200
      camera.up.set 0, 0, 1
      camera.lookAt new THREE.Vector3(0, 0, 200)
      camera.updateProjectionMatrix()

      controls = new THREE.TrackballControls( camera, container );

      controls.rotateSpeed = 1.0;
      controls.zoomSpeed = 1.2;
      controls.panSpeed = 0.8;

      controls.noZoom = false;
      controls.noPan = false;

      controls.staticMoving = true;
      controls.dynamicDampingFactor = 0.3;

      controls.keys = [ 65, 83, 68 ];

      controls.addEventListener( 'change', render );

      # Materials
      unselectedMaterial = new THREE.MeshPhongMaterial(
        specular: '#a9fcff'
        color: '#00abb1'
        emissive: '#006063'
        shininess: 100)
      selectedMaterial = new THREE.MeshPhongMaterial(
        specular: '#a9fcff'
        color: '#abb100'
        emissive: '#606300'
        shininess: 100)
      if !webglContext
        unselectedMaterial.overdraw = 1.0
        selectedMaterial.overdraw = 1.0

      # Arrow = (color, height, ) ->

      # gyroscope model
      model = new THREE.Group()
      do ->
        cone_height = gyroGeometry.length*Math.cos gyroGeometry.angle/2
        cone_radius = gyroGeometry.length*Math.sin gyroGeometry.angle/2
        shift = gyroGeometry.centerMass
        geometry = new THREE.CylinderGeometry cone_radius, 0, cone_height,radiusSegments,heightSegments
        cone = new THREE.Mesh geometry, unselectedMaterial
        cone.rotation.x = pi/2
        cone.position.z = cone_height/2 - shift
        # model.add cone
        size = gyroGeometry.cubesSize
        geometry = new THREE.CubeGeometry size, size, size
        [0,1,2,3].map (i) ->
          cubic = new THREE.Mesh geometry, unselectedMaterial
          cubic.position.z = cone_height - shift
          cubic.position.x = cone_radius * Math.cos pi*i/2
          cubic.position.y = cone_radius * Math.sin pi*i/2
          # model.add cubic
      

      manager = new THREE.LoadingManager()
      manager.onProgress = ( item, loaded, total ) ->
        console.log( item, loaded, total )
      onProgress = ( xhr ) ->
        if xhr.lengthComputable
          percentComplete = xhr.loaded / xhr.total * 100
          console.log Math.round(percentComplete, 2) + '% downloaded'
      onError = (xhr) -> xhr

      loader = new THREE.OBJLoader(manager)
      loader.load( 'gyro.obj', ( object ) ->
        object.traverse ( child ) ->
          if child instanceof THREE.Mesh
            child.material = unselectedMaterial
        object.rotation.x = pi/2
        object.scale.set(14,14,14)
        object.position.z += 113.8
        object.position.z -= gyroGeometry.centerMass
        model.add( object )
      , onProgress, onError )
      scene.add model

      # plane
      do ->
        geometry = new THREE.PlaneGeometry( 300, 300, 32 )
        material = new THREE.MeshBasicMaterial( {color: 0xffff00, side: THREE.DoubleSide} )
        plane = new THREE.Mesh( geometry, material )
        scene.add plane

      do ->
        geometry = new THREE.BufferGeometry()
        positions = new Float32Array( MAX_POINTS * 3 )
        geometry.addAttribute 'position', new THREE.BufferAttribute( positions, 3 )
        geometry.attributes.position.len = 0

        geometry.setDrawRange( 0, 0 )

        material = new THREE.LineBasicMaterial {color: 0xDF4949, linewidth: 2}
        line = new THREE.Line(geometry, material)
        
        x = y = z = index = 0

        for i in [0..MAX_POINTS]
          positions[ index ] = x
          index++
          positions[ index ] = y
          index++
          positions[ index ] = 0
          index++

          x += ( Math.random() - 0.5 ) * 30
          y += ( Math.random() - 0.5 ) * 30
          z += ( Math.random() - 0.5 ) * 30
      scene.add line


      # Ambient light
      ambientLight = new (THREE.AmbientLight)(0x222222)
      scene.add ambientLight
      # Directional light
      directionalLight = new (THREE.DirectionalLight)(0xffffff)
      directionalLight.position.set(1, 1, 1).normalize()
      scene.add directionalLight
      # Used to select element with mouse click
      $('.play').click (el) ->
        console.log 'Clicked'
        $(@).toggleClass 'on'
        simulationState = $(@).hasClass 'on'
        if simulationState == on
          startTime = (new Date).getTime()
          line.geometry.setDrawRange( 0, 0 )
          line.geometry.attributes.position.len = 0
          for k, v of plotData
            console.log k
            v.data = []

      console.log 'loaded'
      [precession, nutation, rotation].map (s) ->
        s.slider = $('#'+s.id+' .knob').CircularSlider
          radius: 50
          animate: off
          value: s.value
          shape: if s.id == 'nutation' then 'Half Circle' else 'Full Circle Right'
          max:   if s.id == 'nutation' then 179
          clockwise: off
          slide: (ui, value) ->
            # if s.id == 'nutation' and value > max_nutation/degree
            #   value = Math.floor value
              # s.slider.setValue value
            s.value = value  
            updateInitialConditions()

      [precessionDot, nutationDot, rotationDot].map (s)->
        $el = $('#'+s.id+' .der-input')
        s.value = parseFloat $el.val()
        $el.on 'change', (el) ->
          s.value = parseFloat $el.val()
          updateInitialConditions()
          # console.log s.id, s.value, $el.val()
      
      updateInitialConditions()

      plot = $('#plot').plot([plotData.theta, plotData.psi]).data("plot")

      render()
      animate()
      return

    animate = ->
      requestAnimationFrame animate
      controls.update()
      render()
      return
    
    getDerivative = (t, [w,x,y,z,p,q,r], [mx,my,mz]) ->
      [wx, wy, wz, xy, yz, xz, w2, x2, y2, z2] = [w*x, w*y, w*z, x*y, y*z, x*z, w*w, x*x, y*y, z*z]
      qs = w2 - x2 - y2 - z2
      M = [
        -my*w2 - 2*mz*wx + my*x2 - 2*mx*xy - my*y2 + 2*mx*wz - 2*mz*yz + my*z2
        mx*w2  + mx*x2 - 2*mz*wy + 2*my*xy - mx*y2 + 2*my*wz + 2*mz*xz - mx*z2
        0
      ]
      pqrd = [
        ( M[0] - J.CB * q * r )/J.A
        ( M[1] - J.AC * r * p )/J.B
        ( M[2] - J.BA * p * q )/J.C
      ]

      quatd = [
        -(p*x + q*y + r*z)/2.0,
        (p*w + r*y - q*z)/2.0,
        (q*w - r*x + p*z)/2.0,
        (r*w + q*x - p*y)/2.0
      ]
      [quatd[0], quatd[1], quatd[2], quatd[3],   pqrd[0], pqrd[1], pqrd[2]]
      
    render = ->
      time = (new Date).getTime()
      t =  (time - startTime)/1000.0
      dt = (time - lastTime) / 1000
      rotationVelocity.precession = 90 * Math.abs( Math.sin pi*nutation.value/180)
      if simulationState
        [w, x, y, z, p, q, r] = stepRungeKutta [
          model.quaternion.w
          model.quaternion.x
          model.quaternion.y
          model.quaternion.z
          omega.x
          omega.y
          omega.z
          ], ( (t,v) -> getDerivative(t,v,[0,0,-weight]) ), time, dt
        
        omega.fromArray [p,q,r]
        model.quaternion.fromArray([x,y,z,w]).normalize()


        cosAngle = w*w - x*x - y*y + z*z
        model.position.z = cosAngle * gyroGeometry.centerMass
        nutAngle = Math.acos(cosAngle)
        psiAngle = Math.atan2 w*y+x*z, w*x-y*z
        proj = gyroGeometry.centerMass*Math.sin nutAngle
        # console.log nutAngle/degree, psiAngle/degree
        vert = [ -proj*Math.sin(psiAngle), proj*Math.cos(psiAngle), 0 ]

        pos = line.geometry.attributes.position

        plotData.theta.data.push [t, nutAngle/degree]
        plotData.psi.data.push [t, psiAngle/degree]
        # console.log nutData
        plot.setData([plotData.theta, plotData.psi])
        plot.setupGrid()
        plot.draw()

        if pos.len < MAX_POINTS
          i = pos.len
          pos.array[3*i+0] = vert[0]
          pos.array[3*i+1] = vert[1]
          pos.array[3*i+2] = vert[2]
          pos.len += 1
          # console.log pos.len
          line.geometry.setDrawRange 0, i+1
          line.geometry.attributes.position.needsUpdate = true
        else
          stopSimulation()

        if nutAngle > max_nutation
          stopSimulation()
          alert "У вас упало"

      # else
      #   q = new THREE.Quaternion()
      #   qaa = (x, y, z, a) ->
      #     new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(x,y,z), a )
      #   q.multiply qaa(0,0,1, Math.PI*precession.value/180)
      #   q.multiply qaa(1,0,0, Math.PI*nutation.value/180)
      #   q.multiply qaa(0,0,1, Math.PI*rotation.value/180)
      #   model.quaternion.copy q
      #   model.position.z = Math.cos(nutation.value*degree) * gyroGeometry.centerMass

      lastTime = time

      renderer.render scene, camera
      return

    updateMaterials = ->
      material = if state.selectedObjects.cube
        selectedMaterial
      else unselectedMaterial
      for child in model.children
        child.material = material

    getGrade = ->
      # The following return value may or may not be used to grade
      # server-side.
      # If getState and setState are used, then the Python grader also gets
      # access to the return value of getState and can choose it instead to
      # grade.
      JSON.stringify state['selectedObjects']

    getState = ->
      JSON.stringify state

    # This function will be called with 1 argument when JSChannel is not used,
    # 2 otherwise. In the latter case, the first argument is a transaction
    # object that will not be used here
    # (see http://mozilla.github.io/jschannel/docs/)

    setState = ->
      stateStr = if arguments.length == 1 then arguments[0] else arguments[1]
      state = JSON.parse(stateStr)
      updateMaterials()
      return

    if window.parent != window
      channel = Channel.build(
        window: window.parent
        origin: '*'
        scope: 'JSInput')
      channel.bind 'getGrade', getGrade
      channel.bind 'getState', getState
      channel.bind 'setState', setState
    init()
    {
      getState: getState
      setState: setState
      getGrade: getGrade
    }

  )