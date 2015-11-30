do ->
  lsum = (vec1, vec2, k1=1) ->
    vec1.map (e, i) -> vec1[i]*k1 + vec2[i]

  stepRungeKutta = (vec, func, t, dt) ->
    k1 = func( t,      vec                )
    k2 = func( t+dt/2, lsum(k1, vec, dt/2) )
    k3 = func( t+dt/2, lsum(k2, vec, dt/2) )
    k4 = func( t+dt,   lsum(k3, vec, dt)   )

    vec.map (e, i) ->
      e + dt*((k1[i]+k4[i])/6 + (k2[i]+k3[i])/3)

  getDerivative = (t, [w,x,y,z,p,q,r], m=1, g=1, l=1) ->
    [A, C] = [J.A, J.C]
    ex=  l* 2*(-w*y+x*z)
    ey=  l* 2*( w*x+y*z)
    ez=  l* w*w - x*w - y*y + z*z

    
    denom = A / m + ex*ex  + ey*ey 

    Mx = g*ey-(p*p+q*q)*ey*ez+r*( (2-C/A)*ex*(q*ex-p*ey)+q*(A-C)/m+q*(ey*ey-ex*ex)+2*p*ex*ey) 
    My =-g*ex+(p*p+q*q)*ex*ez+r*( (2-C/A)*ey*(q*ex-p*ey)-p*(A-C)/m+p*(ey*ey-ex*ex)-2*q*ex*ey) 
    Mz = 0

    quatd = [
      (-p*x - q*y - r*z)/2.0,
      ( p*w + r*y - q*z)/2.0,
      ( q*w - r*x + p*z)/2.0,
      ( r*w + q*x - p*y)/2.0
    ]
    [quatd[0], quatd[1], quatd[2], quatd[3],   Mx/denom, My/denom, Mz/denom ]
  pi = Math.PI
  degree = pi/180
  [sin,cos] = [Math.sin, Math.cos]
  Quaternion = THREE.Quaternion
  Vector = THREE.Vector3

  #Container parameters
  viewportId = 'viewport'
  [width, height] = [400, 300]
  renderer = controls = undefined


  #Objects and constants
  scene = camera = model = line = undefined
  MAX_POINTS = 5000

  #Geometry values
  centerMassHeight = 113.8
  max_nutation = 45*degree

  #Physics parameters
  omega = new Vector(0, 0, 5)
  gyroMass = 1
  gyroG = 10
  gyroL = 1
  J = {
    A: 7
    B: 7
    C: 10
  }
  [J.CB, J.BA, J.AC] = [J.C - J.B, J.B - J.A, J.A - J.C]

  #Plot data
  plot = undefined
  plotData = {
    theta:
      data: [ [0,0] ]
      label: "<span id='theta'>$\\theta = 0.00000$</span>"
      color: 1
    psi:
      data: [ [0,0] ]
      label: "<span id='psi'>$\\psi = 0.00000$</span>"
      color: 0
    phi:
      data: [ [0,0] ]
      label: "<span id='phi'>$\\varphi = 0.00000$</span>"
      color: 3
    phidot:
      data: [ [0,0] ]
      label: "<span id='phidot'>$\\dot\\varphi = 0.00000$</span>"
      color: 2
    # q:
    #   data: [ [0,0] ]
    #   label: "q"
    #   color: 2
  }


  #Simulation parameters
  simulationState = off
  startTime = 0
  resetStartingConditions = on

  #Sync-input objects
  precession    = {id: 'precession', value: 60}
  nutation      = {id: 'nutation', value: 13}
  rotation      = {id: 'rotation', value: 60}
  precessionDot = {id: 'precession', value: -0.53}
  nutationDot   = {id: 'nutation', value: 0.45}
  rotationDot   = {id: 'rotation', value: 2.82}

  #jQuery objects
  $button = $playString = $pauseString = undefined

  toEuler = ([w,x,y,z], [p,q,r]) ->
    theta = Math.acos w*w - x*x - y*y + z*z

    psi = Math.atan2 w*y+x*z, w*x-y*z
    if psi < 0
      psi += 2*pi

    phi = - psi + Math.atan2 2*w*z, w*w-z*z
    until phi > 0
      phi += 2*pi

    phid = r - ( p*Math.sin(phi) + q*Math.cos(phi) )/Math.tan(theta)

    return [psi, theta, phi, phid]

  updateInitialConditions = () ->
    psi   = precession.value*degree
    theta = nutation.value*degree
    phi   = rotation.value*degree
    
    psid   = precessionDot.value
    thetad = nutationDot.value
    phid   = rotationDot.value

    omega.x = psid * sin(theta)*sin(phi) + thetad * cos(phi)
    omega.y = psid * sin(theta)*cos(phi) - thetad * sin(phi)
    omega.z = psid * cos(theta) + phid

    q = new Quaternion()
    f = (x, y, z, a) ->
      new Quaternion().setFromAxisAngle new Vector(x,y,z), a
    q.multiply f(0,0,1, psi)
    q.multiply f(1,0,0, theta)
    q.multiply f(0,0,1, phi)

    model.quaternion.copy q
    model.position.z = Math.cos(theta) * centerMassHeight

    [w,x,y,z] = [q.w, q.x, q.y, q.z]
    psiAngle = Math.atan2 w*y+x*z, w*x-y*z
    if psiAngle < 0
      psiAngle += 2*pi

    nutAngle = Math.acos w*w - x*x - y*y + z*z
    phiAngle = Math.atan2(2*w*z, w*w-z*z) - psiAngle
    until phiAngle > 0
      phiAngle += 2*pi

    phidot = omega.z - ( omega.x*Math.sin(phiAngle) + omega.y*Math.cos(phiAngle) )/Math.tan(nutAngle)

    console.log phidot


  initModels = (webglContext = yes) ->
    # Materials
    gyroMaterial = new THREE.MeshPhongMaterial(
      specular: '#AFD8F8'
      color: '#AFD8F8'
      emissive: '#132116'
      shininess: 100000)
    unless webglContext
      gyroMaterial.overdraw = 1.0
      planeMaterial.overdraw = 1.0

    # gyroscope model
    model = new THREE.Group()
    loader = new THREE.OBJLoader()
    loader.load 'gyro.obj', ( object ) ->
      object.traverse ( child ) ->
        if child instanceof THREE.Mesh
          child.material = gyroMaterial
      object.rotation.x = pi/2
      object.scale.set(14,14,14)
      object.position.z += 113.8
      object.position.z -= centerMassHeight
      model.add object
      scene.add model

    # plane
    do ->
      geometry = new THREE.PlaneGeometry( 300, 300, 32 )
      material = new THREE.MeshBasicMaterial( {color: 0xE0E0E0, side: THREE.DoubleSide} )
      plane = new THREE.Mesh( geometry, material )
      scene.add plane

    do ->
      geometry = new THREE.BufferGeometry()
      positions = new Float32Array MAX_POINTS * 3
      geometry.addAttribute 'position', new THREE.BufferAttribute( positions, 3 )
      geometry.attributes.position.len = 0

      geometry.setDrawRange 0, 0

      material = new THREE.LineBasicMaterial {color: 0xCB4B4B, linewidth: 2}
      line = new THREE.Line(geometry, material)
      scene.add line

  pushButton = (state) ->
    if state == on
      $button.addClass 'on'
      $playString.hide()
      $pauseString.show()
    else
      $button.removeClass 'on'
      $pauseString.hide()
      $playString.show()


  startSimulation = ()->
    simulationState = on
    pushButton on
    startTime = (new Date).getTime()
    console.log startTime
    line.geometry.setDrawRange 0, 0
    line.geometry.attributes.position.len = 0
    for k, v of plotData
      # console.log k
      v.data = []

  stopSimulation = () ->
    simulationState = off
    pushButton off



  $(()->    
    startTime = (new Date).getTime()
    plot = undefined
    plotOptions = undefined
    plotDataArray = []
    plotLegend = undefined
    nutData = []    

    lastTime = 0
    state = 'selectedObjects':
      'cylinder': false
      'cube': false
    channel = undefined
    # Establish a channel only if this application is embedded in an iframe.
    # This will let the parent window communicate with this application using
    # RPC and bypass SOP restrictions.

    plotRedrawAxes = (redraw = false) ->
      plotDataArray.map (data) ->
        data.data.map ([x,y])->
          if x < plotOptions.xaxis.min
            plotOptions.xaxis.min = Math.floor x
            redraw = yes
          if x > plotOptions.xaxis.max
            plotOptions.xaxis.max = Math.ceil x
            redraw = yes
          if y < plotOptions.yaxis.min
            plotOptions.yaxis.min = 30.0*Math.floor y/30.0
            redraw = yes
          if y > plotOptions.yaxis.max
            plotOptions.yaxis.max = 30.0*Math.ceil y/30.0
            redraw = yes
      if redraw
        plot = $.plot '#plot-placeholder', plotDataArray, plotOptions
        if plotLegend
          $("#plot-placeholder .legend").replaceWith(plotLegend)
          # console.log "finished"
          MathJax.Hub.Queue ["Typeset", MathJax.Hub], ()->
            for key, series of plotData
              console.log "span##{key} span.mn:contains('0.00000')"
              series.legendElement = plotLegend.find("span##{key} span.mn:contains('0.00000')")


    plotInit = () ->
      plotDataArray = [plotData.theta, plotData.psi, plotData.phi, plotData.phidot]
      console.log plotDataArray
      plotOptions =
        legend:
          show: yes
        series:
          lines:
            show: on
          points:
            show: off
        xaxis:
          min: 0
          max: 2
        yaxis:
          ticks: 10
          min: 0
          max: 30
        selection:
          mode: "xy"
        zoom:
          interactive: yes
        pan:
          interactive: no
        crosshair:
          mode: "x"
        grid:
          hoverable: yes
          autoHighlight: no
        hooks:
          bindEvents:[
            (p, eHolder) ->
              eHolder.dblclick () ->
                plot = $.plot "#plot-placeholder", startData, options
            ]
          draw: [
            (p, context) ->
              if not plotLegend
                ll = $('#plot-placeholder .legend')
                MathJax.Hub.Typeset(ll.get()[0])
                plotLegend = ll.clone()
                # console.log plotLegend.find("span#theta span:contains('0.00000')")

                # console.log plotLegend.html()
            ]

      plotRedrawAxes(true)

      $("#plot-placeholder").bind "plotselected",  (event, ranges) ->
        console.log 'selected'
        if (ranges.xaxis.to - ranges.xaxis.from < 0.00001)
          ranges.xaxis.to = ranges.xaxis.from + 0.00001
        if (ranges.yaxis.to - ranges.yaxis.from < 0.00001)
          ranges.yaxis.to = ranges.yaxis.from + 0.00001
        plot = $.plot "#plot-placeholder", plotDataArray,
          $.extend true, {}, plotOptions,
            xaxis: { min: ranges.xaxis.from, max: ranges.xaxis.to }
            yaxis: { min: ranges.yaxis.from, max: ranges.yaxis.to }
        $("#plot-placeholder .legend").replaceWith(plotLegend)
      
      updateLegendTimeout = latestPosition = null
      
      updateLegend = ()->
        # console.log 
        updateLegendTimeout = null
        pos = latestPosition

        axes = plot.getAxes()
        if  pos.x < axes.xaxis.min || pos.x > axes.xaxis.max || \
            pos.y < axes.yaxis.min || pos.y > axes.yaxis.max
          return

        
        for key, series of plotData
          if series.data.length == 0
            break
          if pos.x < series.data[0][0]
            [x,y] = series.data[0]
          else if pos.x > series.data[series.data.length-1][0]
            [x,y] = series.data[series.data.length-1]
          else
            for i in [0...series.data.length]
              if series.data[i][0] > pos.x
                break
            p1 = series.data[i - 1]
            p2 = series.data[i]
            x = pos.x
            y = p1[1] + (p2[1] - p1[1]) * (x - p1[0]) / (p2[0] - p1[0])
            
            series.legendElement.text( y.toFixed(4) )
                

      $("#plot-placeholder").bind "plothover", (event, pos, item) ->
        latestPosition = pos
        unless updateLegendTimeout
          updateLegendTimeout = setTimeout updateLegend, 50

      # $('#butt').click ()->
      #   console.log 'click'
      #   plot = $.plot "#plot-placeholder", startData, options

    init = ->
      container = document.getElementById viewportId
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

      initModels webglContext

      # Ambient light
      ambientLight = new THREE.AmbientLight(0x222222)
      scene.add ambientLight
      # Directional light
      directionalLight = new THREE.DirectionalLight(0xffffff)
      directionalLight.position.set(1, 1, 1).normalize()
      scene.add directionalLight
      # Used to select element with mouse click


      $button = $('.play')
      $button.click (el) ->
        console.log 'Clicked'
        # simulationState = $(@).hasClass 'on'
        if simulationState == on
          stopSimulation()
        else
          startSimulation()
      $playString  = $('span#play')
      $pauseString = $('span#pause')

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
        $el.val( s.value.toFixed 3 ) 
        $el.on 'change', (el) ->
          s.value = parseFloat $el.val()
          updateInitialConditions()
          # console.log s.id, s.value, $el.val()
      
      updateInitialConditions()
      plotInit()
      

      render()
      animate()
      return

    animate = ->
      requestAnimationFrame animate
      controls.update()
      render()
      return
      
    render = ->
      time = (new Date).getTime()
      t =  (time - startTime)/1000.0
      dt = (time - lastTime) / 1000
      # rotationVelocity.precession = 90 * Math.abs( Math.sin pi*nutation.value/180)
      if simulationState
        [w, x, y, z, p, q, r] = stepRungeKutta [
          model.quaternion.w
          model.quaternion.x
          model.quaternion.y
          model.quaternion.z
          omega.x
          omega.y
          omega.z
          ], ( (t,v) -> getDerivative(t,v,gyroMass,gyroG,gyroL) ), time, dt
        
        omega.fromArray [p,q,r]
        model.quaternion.fromArray([x,y,z,w]).normalize()

        [psi, theta, phi, phid] = toEuler [w,x,y,z], [p,q,r]

        model.position.z = centerMassHeight * Math.cos theta

        proj = centerMassHeight*Math.sin theta
        vert = [ -proj*Math.sin(psi), proj*Math.cos(psi), 0 ]

        pos = line.geometry.attributes.position

        plotData.theta.data.push [t, theta/degree]
        plotData.psi  .data.push [t, psi/degree]
        plotData.phi  .data.push [t, phi/degree]
        plotData.phidot.data.push [t, phid]

        # console.log nutData
        plot.setData plotDataArray
        # plot.setupGrid()
        plotRedrawAxes()
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

        if theta > max_nutation
          stopSimulation()
          alert "У вас упало"

      lastTime = time

      renderer.render scene, camera
      return

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