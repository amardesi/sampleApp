const gulp = require('gulp')
const sourcemaps = require('gulp-sourcemaps')
const del = require('del')
const babel = require('gulp-babel')
const sass = require('gulp-sass')
const livereload = require('gulp-livereload')
const exec = require('child_process').exec
const spawn = require('child_process').spawn
const wait = require('gulp-wait')
 
var paths = {
  templates: ['templates/*.jsx'],
  styles: ['styles/*.scss']
}

var sinatraProc
var expressProc

// Not all tasks need to use streams
// A gulpfile is just another node program and you can use any package available on npm
gulp.task('clean', function() {
  // You can use multiple globbing patterns as you would with `gulp.src`
  return del(['public/css/*', 'public/js/*'])
})

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

gulp.task('styles', function () {
  gulp.src(paths.styles)
    .pipe(sass().on('error', sass.logError))
    .pipe(gulp.dest('public/css'))
    .pipe(livereload())
})

// Rerun the task when a file changes
gulp.task('watch', function() {
  livereload.listen()
  gulp.watch(paths.templates, ['templates'])
  gulp.watch(paths.styles, ['styles'])
})

gulp.task('sinatra', function() {
  sinatraProc = spawn('ruby', ['escholApp.rb', '-p', '4001'], { stdio: 'inherit' })
})

gulp.task('express', function() {
  expressProc = spawn('node', ['escholIso.js'], { stdio: 'inherit' })
  expressProc.on('exit', function() {
    expressProc = null
  })
})

// The default task (called when you run `gulp` from cli)
gulp.task('default', ['watch', 'templates', 'styles', 'sinatra', 'express'])
