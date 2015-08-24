module.exports = (grunt) ->
    # Configuration
    config =
        pkg: grunt.file.readJSON 'package.json'

    config.livescript =
        compile:
            expand: true
            flatten: true
            src: ['src/*.ls']
            dest: 'lib/'
            ext: '.js'

    config.clean =
        lib: ["lib/"]

    grunt.config.init config

    # Load plugins
    grunt.loadNpmTasks 'grunt-livescript'
    grunt.loadNpmTasks 'grunt-contrib-clean'

    # Register tasks
    grunt.registerTask 'default', [
        'build'
    ]

    grunt.registerTask 'build', [
        'clean:lib'
        'livescript:compile'
    ]