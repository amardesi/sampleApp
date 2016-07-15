// Build process for eschol sample app

// Import required modules.
const gulp = require('gulp')
const sourcemaps = require('gulp-sourcemaps')
const del = require('del')
const babel = require('gulp-babel')
const sass = require('gulp-sass')
const livereload = require('gulp-livereload')
const exec = require('child_process').exec
const spawn = require('child_process').spawn
const wait = require('gulp-wait')
 
// Paths to the resources we are going to compile
var paths = {
  templates: ['templates/*.jsx'],
  styles: ['styles/*.scss']
}

// Processes we will start up
var sinatraProc // Main app in Sinatra (Ruby)
var expressProc // Sub-app for isomophic javascript in Express (Node/Javascript)

///////////////////////////////////////////////////////////////////////////////////////////////////
// Clean out (delete) all generated resources.
gulp.task('clean', function() {
  // You can use multiple globbing patterns as you would with `gulp.src`
  return del(['public/css/*', 'public/js/*'])
})

///////////////////////////////////////////////////////////////////////////////////////////////////
// Translate React templates in JSX and ES2015 extensions, to plain-old Javascript that can run in
// practically any browser. These end up in the public/js directory.
gulp.task('templates', function() {
  gulp.src(paths.templates)
    .pipe(sourcemaps.init())
    .pipe(babel({
      presets: ['react', 'es2015']
    }))
    .on('error', function(err) {
      console.log("" + err)
      this.emit('end')
    })
    .pipe(sourcemaps.write('.'))
    .pipe(gulp.dest('public/js'))
    .on('end', function() {
        livereload.reload()
    })
})

///////////////////////////////////////////////////////////////////////////////////////////////////
// Translate SCSS templates to plain old CSS, using SASS. These end up in the public/css directory.
gulp.task('styles', function () {
  gulp.src(paths.styles)
    .pipe(sass().on('error', sass.logError))
    .pipe(gulp.dest('public/css'))
    .pipe(livereload())
})

///////////////////////////////////////////////////////////////////////////////////////////////////
// Rerun the the translation tasks when a file changes. Also triggers a LiveReload reload so the
// browser will refresh right away.
gulp.task('watch', function() {
  livereload.listen()
  gulp.watch(paths.templates, ['templates'])
  gulp.watch(paths.styles, ['styles'])
})

///////////////////////////////////////////////////////////////////////////////////////////////////
// Fire up the main app in Sinatra (Ruby).
gulp.task('sinatra', function() {
  sinatraProc = spawn('ruby', ['escholApp.rb', '-p', '4001'], { stdio: 'inherit' })
})

///////////////////////////////////////////////////////////////////////////////////////////////////
// Fire up the isomorphic sub-app in Node/Express (Javascript)
gulp.task('express', function() {
  expressProc = spawn('node', ['escholIso.js'], { stdio: 'inherit' })
  expressProc.on('exit', function() {
    expressProc = null
  })
})

///////////////////////////////////////////////////////////////////////////////////////////////////
// The default task (called when you run `gulp` from cli)
gulp.task('default', ['watch', 'templates', 'styles', 'sinatra', 'express'])
