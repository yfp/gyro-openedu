module.exports = function(grunt) {

  grunt.initConfig({
    uglify: {
      my_target : {
        options : {
        },
        files: {
          'composite.min.js':
            ['Gruntfile.js',
            'canvasrenderer.js',
            'circular-slider.js', 
            'flot/jquery.flot.min.js',
            'flot/jquery.flot.selection.min.js',
            'jquery.flot.navigate.js',
            'flot/jquery.flot.crosshair.min.js',
            'jschannel.js',
            'three.min.js',
            'objloader.js',
            'trackball_controls.js',
            'physics.js'
              ]
          }
      }
    }
  });
  grunt.loadNpmTasks('grunt-contrib-uglify');
};