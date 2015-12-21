Promise = require 'bluebird'
{ expect } = require 'chai'
_ = require 'lodash'
fs = require 'fs'
tk = require 'timekeeper'
es = require 'event-stream'

{ parseEventStream } = require '../lib/docker-event-stream'
{ createNode, createTree, annotateTree } = require '../lib/docker-image-tree'
{ createCompare, merge, lruSort } = require '../lib/lru'

describe 'createCompare', ->
	it 'should return a function', ->
		expect(createCompare(1, 0)).to.be.a('function')

	it 'should compare based on mtime', ->
		comp = createCompare(1, 0)
		a = createNode('a')
		a.mtime = 5

		b = createNode('b')
		b.mtime = 3

		expect(comp(a, b)).to.equal(a.mtime - b.mtime)

	it 'should compare based on size', ->
		comp = createCompare(0, 0)
		a = createNode('a')
		a.mtime = 5
		a.size = 10

		b = createNode('b')
		b.mtime = 3
		b.size = 7

		expect(comp(a, b)).to.equal(-3)

	it 'should compare based on mtime if `a.mtime` above threshold', ->
		comp = createCompare(0, 30000)

		a = createNode('a')
		a.mtime = Date.UTC(2016, 0, 1)
		a.size = 10

		b = createNode('b')
		b.mtime = 3
		b.size = 7

		tk.freeze(Date.UTC(2016, 0, 1, 0, 0, 15))
		expect(comp(a, b)).to.equal(a.mtime - b.mtime)
		tk.reset()

	it 'should compare based on mtime if `b.mtime` above threshold', ->
		comp = createCompare(0, 30000)

		a = createNode('a')
		a.mtime = 3
		a.size = 10

		b = createNode('b')
		b.mtime = Date.UTC(2016, 0, 1)
		b.size = 7

		tk.freeze(Date.UTC(2016, 0, 1, 0, 0, 15))
		expect(comp(a, b)).to.equal(a.mtime - b.mtime)
		tk.reset()

	it 'should compare based on the weight function', ->
		comp = createCompare(0.5, 0)

		a = createNode('a')
		a.mtime = 10
		a.size = 10

		b = createNode('b')
		b.mtime = 5
		b.size = 7

		tk.freeze(Date.UTC(2016, 0, 1, 0, 0, 15))
		expect(comp(a, b)).to.equal(1)
		tk.reset()

describe 'merge', ->
	before ->
		@compare = (a, b) -> a - b

	it 'should merge []', ->
		expect(merge([], @compare)).to.deep.equal([])
	it 'should merge [[],[],...]', ->
		expect(merge([ [], [] ], @compare)).to.deep.equal([])
	it 'should merge [[a],[],[],...]', ->
		expect(merge([ [0],[],[] ], @compare)).to.deep.equal([0])
	it 'should merge arrays of sorted numbers', ->
		expect(merge([ [1,3,5],[2,4,6] ], @compare)).to.deep.equal([1,2,3,4,5,6])
	it 'should merge unsorted numbers in the order they were given', ->
		expect(merge([ [5,3,1],[4,6,2] ], @compare)).to.deep.equal([4,5,3,1,6,2])

describe 'lruSort', ->
	before ->
		@compare = createCompare(1, 0)

	it 'should sort a single node', ->
		a = createNode('a')

		ret_a = _.clone(a)
		delete ret_a.children

		expect(lruSort(a, @compare)).to.deep.equal([ret_a])

	it 'should sort a root node with two children', ->
		a = createNode('a')
		a.size = 2
		a.mtime = 2

		b = createNode('b')
		b.size = 7
		b.mtime = 3

		c = createNode('c')
		c.size = 10
		c.mtime = 5

		a.children['b'] = b
		a.children['c'] = c

		ret_b = _.clone(b)
		delete ret_b.children

		ret_c = _.clone(c)
		ret_c.size += a.size
		delete ret_c.children

		ret = lruSort(a, @compare)
		expect(ret).to.deep.equal([ret_b, ret_c])

	it 'should sort a real tree with multiple tags', ->
		input = require('./fixtures/docker-images.json')
		tree = createTree(input)

		new Promise (resolve, reject) ->
			mtimes = null

			fs.createReadStream(__dirname + '/fixtures/docker-events.json')
			.pipe(parseEventStream())
			.on 'error', reject
			.pipe es.mapSync (data) ->
				mtimes = data
			.on 'end', -> resolve(mtimes)
			.on 'error', reject
		.then (layer_mtimes) =>
			tk.freeze(Date.UTC(2016, 0, 1))
			annTree = annotateTree(layer_mtimes, tree)
			tk.reset()

			ret = lruSort(annTree, @compare)
			output = [
				{
					"id": "9a61b6b1315e6b457c31a03346ab94486a2f5397f4a82219bee01eead1c34c2e",
					"repoTags": [
						"resin/project3"
					],
					"size": 125151141,
					"mtime": 1448576073000
				},
				{
					"id": "80dc79d29cd8618e678da508fc32f7289e6f72defb534f3f287731b1f8b355ea",
					"repoTags": [],
					"size": 98872,
					"mtime": 1451606400000
				},
				{
					"id": "6d41a4a0bf8168363e29da8a5ecbf3cd6c37e3f5a043decd5e7da6e427ba869c",
					"repoTags": [
						"project2"
					],
					"size": 330389,
					"mtime": 1448576073000
				},
				{
					"id": "e53bd4df04f86919156c4510cdc6e6c9491ec8ec226381d36aca573b46bbbbbc",
					"repoTags": [
						"project1"
					],
					"size": 125151141,
					"mtime": 1451606400000
				}
			]

			expect(ret).to.deep.equal(output)
