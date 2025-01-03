"use strict";

make_controls()
add_svg()
reload()

function reload() {
    clear_svg()
    resize_svg()
    // load stub
    load_by_path(stub => {
        // load data
        d3.json('../' + stub.out + "/" + stub.path)
        .then(data => {
            // load summary
            d3.json('../' + stub.out + "/summary.json")
                .then(summary => {
                    show_data(stub, data, summary)
            })
        })
    })
}



function make_controls() {
    add_controls()
    let controls = get_controls()
    controls.selectAll("*").remove()
    controls.append("span")
        .text("Search: ")
        .attr("id", "search-input")
        .append("input")
        .style("width", 500)
        .on("input", () => reload())
    controls.append("span")
        .text("Temp:")
        .attr("id", "temperature-input")
        .append("input")
        .property("value", "config")
        .style("width", 50) 
        .on("input", () => reload())
}

let search_input = ""
let ancestor_set = new Set()
let descendant_set = new Set()
let selected_set = new Set()

/// Propagate the selected set to the ancestor and descendant sets
function propagate_selected(history) {
    let descendant_worklist = []
    for (let state of history) {
        for (let particle of state.particles) {
            if (selected_set.has(particle.expr_id)) {
                for (let ancestor = particle.parent; ancestor != undefined; ancestor = ancestor.parent) {
                    ancestor_set.add(ancestor.expr_id)
                }
                descendant_worklist.push(...particle.children)
            }
        }
    }
    while (descendant_worklist.length > 0) {
        let particle = descendant_worklist.pop()
        if (descendant_set.has(particle.expr_id))
            continue
        descendant_set.add(particle.expr_id)
        descendant_worklist.push(...particle.children)
    }
}

// add "Esc" listener to overall sindow
window.addEventListener("keydown", function (event) {
    if (event.key == "Escape") {
        selected_set.clear()
        ancestor_set.clear()
        descendant_set.clear()
        reload()
    }
})


function show_data(stub, data, summary) {
    window.stub = stub
    window.data = data
    window.summary = summary

    let config_temps = summary.config.resample_temperature
    let T;
    if (d3.select("#temperature-input input").property("value") == "config") {
        T = Number(config_temps.temps[0])
        if (config_temps.temps.length > 1) {
            console.log("Warning: multiple temperatures in config, using first")
            // insert that warning too
            d3.select("#controls").append("div")
                .text("Warning: multiple temperatures in config, using first: " + e)
                .style("color", "red")
        }
        d3.select("#temperature-input input").property("value", T)
    } else {
        T = Number(d3.select("#temperature-input input").property("value"))
    }
    search_input = d3.select("#search-input input").property("value")

    const g_smc = get_foreground().append("g").attr("id", "smc")
    g_smc.attr("transform", `translate(${800},${100}) scale(.5)`)

    d3.selectAll(".regex-error").remove()
    d3.select("#search-input input").style("background-color", "")

    // report broken search input with try catch
    try {
        new RegExp(search_input)
    } catch (e) {
        console.log("Invalid Search Input (use JavaScript Regex syntax): " + e)
        d3.select("#search-input input").style("background-color", "pink")
        d3.select("#controls").append("div")
            .classed("regex-error", true)
            .text("Invalid JavaScript Regex Expression: " + e)
            .style("color", "red")
        return
    }

    let history = data.history
    let expr_ids = data.expr_ids
    window.svg = history


    if (window.location.pathname.startsWith("/out/")) {
        let out_html_file = window.location.pathname
        let shared_html_file = "/html/smc.html"
        let outdir = out_html_file.replace('html/smc.html', '')
        let target_file = url_params.get("path")
        // make a link to put this in terms of the shared html file
        let shared_html_link = shared_html_file + "?path=" + outdir + target_file
        d3.select("#controls").append("a")
            .attr("href", shared_html_link)
            .text("Shared HTML Version")
    }


    const top_k_particles = Number(d3.select("#top-k-input input").property("value"))

    const num_particles = history[0].particles.length

    const particle_yspace = 30
    const state_yspace = particle_yspace * (top_k_particles + 1) + 50

    for (let i = 0; i < history.length; i++) {
        const fieldnames = history[i].fieldnames
        for (let j = 0; j < num_particles; j++) {
            if (fieldnames != undefined) {
                const new_particle = {}
                if (fieldnames.length != history[i].particles[j].length)
                    throw new Error("fieldnames and particle length mismatch")
                for (let k = 0; k < fieldnames.length; k++) {
                    new_particle[fieldnames[k]] = history[i].particles[j][k]
                }
                history[i].particles[j] = new_particle
            }
            if (expr_ids != undefined) {
                history[i].particles[j].expr_id = history[i].particles[j].expr - 1
                history[i].particles[j].expr = expr_ids[history[i].particles[j].expr_id]
            }

            history[i].particles[j].search_hit = search_input.length > 0 && history[i].particles[j].expr.search(search_input) != -1

            // check if its a string
            if (typeof history[i].particles[j].expr != "string")
                throw new Error("expr is not a string")
            history[i].particles[j].children = []
        }
    }

    function set_parent_child(parent, child) {
        child.parent = parent
        parent.children.push(child)
    }

    // cut out any initial/final resamples
    while (history[0].mode == "resample")
        history.splice(0, 1)
    while (history[history.length - 1].mode == "resample")
        history.splice(history.length - 1, 1)

    // loop over all but last particle. At each step we're treaing `i` as the parent and figuring out who its child should be.
    let i = 0
    while (i < history.length - 1) {
        if (history[i].mode == "resample")
            throw new Error("should be impossible since we stripped leading resamples")
        if (history[i + 1].mode == "resample") {
            if (i + 2 >= history.length)
                throw new Error("should be impossible since we stripped trailing resamples")
            if (history[i + 2].mode == "resample")
                throw new Error("two resamples in a row shouldnt be possible")
            // lets splice out this resample and connect i to i+2. The child is i+2. The parent is
            // taken from `i` but which of those parents is used is taken from i+1
            for (let j = 0; j < num_particles; j++) {
                set_parent_child(history[i].particles[history[i + 1].ancestors[j] - 1], history[i + 2].particles[j])
            }
            // now we splice out `i+1`
            history.splice(i + 1, 1)
            // and since `i` is handled, we can just increment to move onto handling i+1 (formerly called i+2)
            i += 1
        } else {
            // not a resample. This is a normal step so we just want to connect up i to i+1
            for (let j = 0; j < num_particles; j++) {
                set_parent_child(history[i].particles[j], history[i + 1].particles[j])
            }
            // now we move onto i+1
            i += 1
        }
    }

    for (let state of history) {
        for (let particle of state.particles) {
            particle.selected = selected_set.has(particle.expr_id)
            particle.selected_ancestor = ancestor_set.has(particle.expr_id)
            particle.selected_descendant = descendant_set.has(particle.expr_id)
        }
    }

    // update curr_highlighted if its already been set
    if (curr_highlighted != undefined) {
        curr_highlighted = history[curr_highlighted.i].particles[curr_highlighted.j]
    }

    // modify `data` in place in any ways you need
    for (let i = 0; i < history.length; i++) {

        let particles = history[i].particles
        history[i].logweight_total = particles.reduce((acc, p) => logaddexp(acc, p.logweight), -Infinity)

        history[i].x = 0
        history[i].y = i * state_yspace

        for (let j = 0; j < particles.length; j++) {
            const particle = particles[j]

            particle.visible = false

            for (const [k, v] of Object.entries(particles[j]))
                particles[j][k] = null_to_neginf(v)

            particle.relative_weight = Math.exp(particle.logweight - history[i].logweight_total)
            particle.prefix = particle.expr.split("<<<")[0]
            particle.suffix = particle.expr.split(">>>")[1]
            particle.highlighted = particle.expr.split(">>>")[0].split("<<<")[1]
            particle.i = i
            particle.j = j
        }

        // add in the ones that are highlighted
        if (curr_highlighted != undefined) {
            // add all ancestors
            for (let ancestor = curr_highlighted; ancestor != undefined; ancestor = ancestor.parent) {
                if (ancestor.i == i && !sorted.includes(ancestor))
                    sorted.push(ancestor)
            }
        }
    }

    g_smc.selectAll("*").remove()

    if (curr_highlighted != undefined) {
        let to_highlight = curr_highlighted
        curr_highlighted = undefined
        set_click_highlight(to_highlight, true, false) // no redraw, that would make a loop
    }


    // summary graphs to left of particles
    for (let i = 0; i < history.length; i++) {
        const state = history[i]
        const particles = state.particles
        let g_step = g_smc.append("g")
            .attr("transform", `translate(${-1400},${state.y})`)

        let min_loglikelihood = Math.floor(log2(history[0].particles[0].likelihood) - 1)
        let max_loglikelihood = Math.floor(0.0)


        let logweight_total = logsumexp(particles.map(p => p.logweight / T))


        let binner = d3.bin()
            .value(d => {
                let ll = log2(d.likelihood)
                if (ll < min_loglikelihood)
                    return min_loglikelihood
                return ll
            })
            .domain([min_loglikelihood, max_loglikelihood])

        let bins_large = binner.thresholds(20)(particles)
        let bins_small = binner.thresholds(max_loglikelihood - min_loglikelihood)(particles)

        let graph = makeGraph({ g: g_step, height: 150, width: 500, xmin: min_loglikelihood, xmax: max_loglikelihood, ymin: 0, ymax: 1, title: "Likelihood", data: particles.map(p => p.likelihood) })
        graph.g.selectAll(".tick text")
            .style("font-size", 10)
        graph.g.selectAll(".tick line,path,text")
            .style("opacity", 0.5)

        function dedup_particles(bin) {
            bin.subbins = []
            bin.sort((a, b) => a.expr_id - b.expr_id)
            let curr_id = -1
            for (let particle of bin) {
                if (particle.expr_id != curr_id) {
                    curr_id = particle.expr_id
                    bin.subbins.push({
                        copies: [],
                        expr_id: curr_id,
                        first: particle,
                    })
                }
                let subbin = bin.subbins[bin.subbins.length - 1]
                subbin.copies.push(particle)
                particle.subbin = subbin
                // subbin.logweight = logaddexp(subbin.logweight, particle.logweight)
                if (subbin.copies[0].likelihood != particle.likelihood)
                    throw new Error("likelihood mismatch")
            }
            bin.subbins.sort((a, b) => b.copies.map(p => p.logweight / T).reduce(logaddexp, -Infinity) - a.copies.map(p => p.logweight / T).reduce(logaddexp, -Infinity))
            bin.sort((a, b) => b.logweight / T - a.logweight / T)
        }


        for (let j = 0; j < bins_large.length; j++) {
            let bin = bins_large[j]
            dedup_particles(bin)

            let x = graph.xScale(bin.x0)
            let logweight_bin = bin.map(p => p.logweight / T).reduce(logaddexp, -Infinity)
            let relative_weight_bin = Math.exp(logweight_bin - logweight_total)
            let y = graph.yScale(relative_weight_bin)
            let width = graph.xScale(bin.x1) - graph.xScale(bin.x0)
            let height = graph.yScale(0) - y

            let subset_predicate = p => false
            let subset_color = "none"
            if (bin.filter(p => p.selected).length > 0) {
                subset_predicate = p => p.selected
                subset_color = "rgb(116, 184, 0)"
            } else if (bin.filter(p => p.selected_ancestor).length > 0) {
                subset_predicate = p => p.selected_ancestor
                subset_color = "rgb(216, 184, 0)"
            } else if (bin.filter(p => p.selected_descendant).length > 0) {
                subset_predicate = p => p.selected_descendant
                subset_color = "rgb(216, 184, 0)"
            } else if (search_input.length > 0) {
                subset_predicate = p => p.search_hit
                subset_color = "red"
            }

            let logweight_subset = bin.filter(subset_predicate).map(p => p.logweight / T).reduce(logaddexp, -Infinity)
            let relative_weight_subset = Math.exp(logweight_subset - logweight_total)
            let y_subset = graph.yScale(relative_weight_subset)
            let height_subset = graph.yScale(0) - y_subset

            let uid = `bin-${i}-${j}`
            let anchor = make_anchor(graph.g, x + width, y, uid, anchor => {
                for (const subbin of bin.subbins) {
                    let subbin_logweight = subbin.copies.map(p => p.logweight / T).reduce(logaddexp, -Infinity)
                    let text = anchor.g_box.append("text")
                        .classed("program", true)
                        .classed("hover", true)
                        .classed("likelihood-zero", subbin.first.likelihood == 0)
                        .classed("search-hit", subbin.first.search_hit)
                        .classed("selected", subbin.first.selected)
                        .classed("selected-ancestor", subbin.first.selected_ancestor)
                        .classed("selected-descendant", subbin.first.selected_descendant)
                        .attr("y", anchor.g_box.node().getBBox().height)
                        .on("dblclick", () => set_selected([subbin.first]))
                    text.append("tspan")
                        .style("fill", "black")
                        .text(subbin.copies.length + "→")
                    text.append("tspan")
                        .style("fill", "black")
                        .text(showN(Math.exp(subbin_logweight - logweight_total) * num_particles) + " ")
                    text.append("tspan")
                        .style("fill", "black")
                        .text("γ=" + log2(subbin.first.posterior).toFixed(0) + " (" + log2(subbin.first.prior).toFixed(0) + "+" + log2(subbin.first.likelihood).toFixed(0) + ") w=" + log2(Math.exp(subbin_logweight)).toFixed(0) + " ")
                    text.append("tspan")
                        .text(subbin.first.prefix)
                    text.append("tspan")
                        .classed("modified-expr", true)
                        .text(subbin.first.highlighted)
                    text.append("tspan")
                        .text(subbin.first.suffix)
                }
            })

            function set_selected(particles) {
                selected_set.clear()
                ancestor_set.clear()
                descendant_set.clear()
                for (const p of particles) {
                    selected_set.add(p.expr_id)
                }
                propagate_selected(history)
                reload()
            }
            function onclick(event) {
                // if (event.altKey) {
                // set_selected()
                // } else {
                toggle_hover(anchor)
                // }
            }
            function ondblclick(event) {
                set_selected(bin.subbins.map(subbin => subbin.first))
            }

            graph.g.append("rect")
                .attr("x", x)
                .attr("y", y)
                .attr("width", width)
                .attr("height", height)
                .style("fill", "darkblue")
                .style("opacity", 0.2)
                .on("click", onclick)
                .on("dblclick", ondblclick)

            graph.g.append("rect")
                .attr("x", x)
                .attr("y", y_subset)
                .attr("width", width)
                .attr("height", height_subset)
                .style("fill", subset_color)
                .on("click", onclick)
                .on("dblclick", ondblclick)

            if (bin.length > 0) {
                graph.g.append("text")
                    .attr("x", x + width / 2)
                    .attr("y", y - 5)
                    .attr("text-anchor", "middle")
                    .style("font-size", 8)
                    .text(bin.length)
                    .on("click", onclick)
                    .on("dblclick", ondblclick)
            }
            let num_special = bin.filter(subset_predicate).length
            if (num_special > 0) {
                graph.g.append("text")
                    .attr("x", x + width / 2)
                    .attr("y", y - 14)
                    .attr("text-anchor", "middle")
                    .style("font-size", 8)
                    .style("fill", subset_color)
                    .style("font-weight", "bold")
                    .text("(" + num_special + ")")
                    .on("click", onclick)
                    .on("dblclick", ondblclick)
            }

        }
        for (let j = 0; j < bins_small.length; j++) {
            let bin = bins_small[j]
            let x = graph.xScale(bin.x0)
            let y = graph.yScale(Math.exp(bin.map(p => p.logweight / T).reduce(logaddexp, -Infinity) - logweight_total))
            // let y = graph.yScale(bin.length / particles.length)
            let width = graph.xScale(bin.x1) - graph.xScale(bin.x0)
            let height = graph.yScale(0) - y
            graph.g.append("rect")
                .attr("x", x)
                .attr("y", y)
                .attr("width", width)
                .attr("height", height)
                .style("fill", "darkblue")
                // .on("click", onclick)
                // .on("dblclick", ondblclick)
            // .style("opacity", 0.2)
        }


    }

}

let curr_highlighted = undefined
/// Highlights the history leading up to this particle
function set_click_highlight(particle, highlight = true, redraw = true) {

    if (highlight && curr_highlighted != undefined) {
        set_click_highlight(curr_highlighted, false)
    }
    if (highlight && particle === curr_highlighted) {
        curr_highlighted = undefined
        return
    }
    if (highlight)
        curr_highlighted = particle

    const to_highlight = [particle]
    for (let ancestor = particle; ancestor != undefined; ancestor = ancestor.parent) {
        to_highlight.push(ancestor)
    }
    const worklist = [particle]
    while (worklist.length > 0) {
        let descendant = worklist.pop()
        worklist.push(...descendant.children)
        to_highlight.push(...descendant.children)
    }

    for (const p of to_highlight) {
        if (!p.visible)
            continue
        p.circle.classed("highlighted", highlight)
        p.dotted_line.classed("highlighted", highlight)
        p.text.classed("highlighted", highlight)
        p.weight_bar.classed("highlighted", highlight)
        p.weight_bar_background.classed("highlighted", highlight)
        if (p.parent_line) {
            p.parent_line.classed("highlighted", highlight)
        }
    }

    if (redraw)
        reload()
}