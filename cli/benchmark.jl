using JSON: JSON

using ProbStitch: compress, load_corpus, size

repeats = 10
iterations = 1

function benchmark(path::String, num_particles::Int)
	println(path)
	corpus = load_corpus(path)
	result = () -> compress(
		corpus;
		N = iterations,
		num_particles = num_particles,
	)
	result()
	repeated = []
	for _ in 1:repeats
		start_t = time_ns()
		res = result()
		end_t = time_ns()
		time_taken = (end_t - start_t) / 1e9
		push!(
			repeated,
			Dict(
				"time_taken" => time_taken,
				"corpus_sizes" => [size(res.before), size(res.rewritten)],
				"abstraction_sizes" => [
					round.abstraction.size
					for round in res.rounds
				],
			),
		)
	end
    return repeated
end

function main()
    results_by_n_particles = Dict()
	for n_particles in [10, 20, 50, 100, 200, 500]
		println("n_particles: $n_particles")
		results_all = []
		for path in readdir("data/cogsci")
			if endswith(path, ".json") && !contains(path, "-out")
				result = benchmark(joinpath("data/cogsci", path), n_particles)
				push!(results_all,
					Dict(
						"path" => path,
						"result" => result,
					)
				)
			end
		end
		results_by_n_particles[n_particles] = results_all
	end
    # write to file
    open("analysis_out/cogsci-benchmark-results.json", "w") do io
        JSON.print(io, results_by_n_particles)
    end
end

main()