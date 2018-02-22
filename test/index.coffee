Promise = require 'bluebird'
{ expect } = require 'chai'
_ = require 'lodash'

DockerGC = require('../lib/index')
dockerUtils = require('../lib/docker.coffee')

SKIP_GC_TEST = process.env.SKIP_GC_TEST == '1' || false
IMAGES = [ 'alpine:3.1', 'debian:squeeze', 'ubuntu:lucid' ]

promiseToBool = (p) ->
	p.return(true).catchReturn(false)

pullAsync = (docker, tag) ->
	docker.pull(tag)
	.then (stream) ->
		new Promise (resolve, reject) ->
			stream.resume()
			stream.once('error', reject)
			stream.once('end', resolve)

dockerUtils.getDocker({})
.then (docker) ->
	# This test case is a little weird, it requires that no other images are present on
	# the system to ensure that the correct one is being removed. Because of this, you
	# can use the SKIP_GC_TEST env var to inform the test suite not to run this test
	describe 'Garbage collection', ->
		before ->
			@dockerStorage = new DockerGC()
			# Use either local or CI docker
			@dockerStorage.setDocker({})
			.then =>
				@dockerStorage.setupMtimeStream()

		it 'should remove the LRU image', ->
			this.timeout(600000)
			return Promise.resolve() if SKIP_GC_TEST

			# first pull some images, so we know in which order they are referenced
			Promise.each IMAGES, (image) ->
				pullAsync(docker, image)
			.then =>
				# Attempt to remove a single byte, which will remove the LRU image,
				# which should be alpine
				@dockerStorage.garbageCollect(1)
			.then ->
				Promise.map IMAGES, (image) ->
					promiseToBool(docker.getImage(image).inspect())
			.then (imgs) ->
				if not _.isEqual(imgs, [false, true, true])
					throw new Error('Incorrect images removed!')

		it 'should remove more than one image if necessary', ->
			this.timeout(600000)
			return Promise.resolve() if SKIP_GC_TEST

			# Get the size of the first image, so we can add one to it to remove
			# the next one in addition
			Promise.each IMAGES, (image) ->
				pullAsync(docker, image)
			.then ->
				docker.getImage('alpine:3.1').inspect().get('Size')
			.then (size) =>
				@dockerStorage.garbageCollect(size + 1)
			.then ->
				Promise.map IMAGES, (image) ->
					promiseToBool(docker.getImage(image).inspect())
			.then (imgs) ->
				if not _.isEqual(imgs, [false, false, true])
					throw new Error('Incorrect images removed')

		it 'should get daemon host disk usage', ->
			this.timeout(600000)
			@dockerStorage.getDaemonFreeSpace()
			.then (du) ->
				expect(du).to.be.an('object')
				expect(du).to.have.property('free').that.is.a('number')
				expect(du).to.have.property('used').that.is.a('number')
				expect(du).to.have.property('total').that.is.a('number')

		it 'should get the correct architecture for a remote host', ->
			@dockerStorage.getDaemonArchitecture()
			.then (arch) ->
				expect(arch).to.be.a('string')

		it 'should set a base image to be used', ->
			@dockerStorage.baseImagePromise.then (img) ->
				expect(img).to.be.a('string')

