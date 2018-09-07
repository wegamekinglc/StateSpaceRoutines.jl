"""
```
mutation!(Φ, Ψ, QQ, det_HH, inv_HH, y_t, s_t, s_t1, ϵ_t, c, n_mh_steps;
    parallel = false)
```

Mutate particles by taking Metropolis-Hastings steps in the `ϵ_t` space. This
function modifies `s_t` and `ϵ_t` in place and returns `accept_rate`.
"""
function mutation!(Φ::Function, Ψ::Function, QQ::Matrix{Float64},
                   det_HH::Float64, inv_HH::Matrix{Float64}, y_t::Vector{Float64},
                   s_t::M, s_t1::M, ϵ_t::M, c::Float64, n_mh_steps::Int;
                   parallel::Bool = false) where M<:AbstractMatrix{Float64}
    # Sizes
    n_obs = size(y_t, 1)
    n_particles = size(ϵ_t, 2)

    # Initialize vector of acceptances
    MyVector = parallel ? SharedVector : Vector

    # CHECK
    accept_vec = MyVector{Int}(n_particles)

    # Used to generate new draws of ϵ
    dist_ϵ = MvNormal(c^2 * diag(QQ))

    # Take Metropolis-Hastings steps
    @mypar parallel for i in 1:n_particles
        s_t[:,i], ϵ_t[:,i], accept_vec[i] =
            mh_steps(Φ, Ψ, dist_ϵ, y_t, @view(s_t1[:,i]), @view(s_t[:,i]), @view(ϵ_t[:,i]),
                     det_HH, inv_HH, n_mh_steps)
    end

    # Calculate and return acceptance rate
    accept_rate = sum(accept_vec) / (n_mh_steps*n_particles)
    return accept_rate
end

"""
```
mh_steps(Φ, Ψ, dist_ϵ, y_t, s_t1, s_t, ϵ_t, det_HH, inv_HH, n_mh_steps)
```

Take `n_mh_steps` many steps in the `ϵ_t` space for a single particle. Returns
the new `s_t`, `ϵ_t`, and the number of acceptances `accept`.
"""
function mh_steps(Φ::Function, Ψ::Function, dist_ϵ::MvNormal, y_t::Vector{Float64},
                  s_t1::AbstractVector{Float64}, s_t::AbstractVector{Float64}, ϵ_t::AbstractVector{Float64},
                  det_HH::Float64, inv_HH::Matrix{Float64}, n_mh_steps::Int)
    accept = 0

    # Compute posterior at initial ϵ_t
    post_1::Float64 = fast_mvnormal_pdf(y_t - Ψ(s_t), det_HH, inv_HH)
    post_2::Float64 = fast_mvnormal_pdf(ϵ_t)
    post::Float64   = post_1 * post_2

    for j = 1:n_mh_steps
        # Draw ϵ_new and s_new
        ϵ_new::AbstractVector{Float64} = ϵ_t + rand(dist_ϵ)
        s_new::AbstractVector{Float64} = Φ(s_t1, ϵ_new)

        # Calculate posterior
        post_new_1::Float64 = fast_mvnormal_pdf(y_t - Ψ(s_new), det_HH, inv_HH)
        post_new_2::Float64 = fast_mvnormal_pdf(ϵ_new)
        post_new::Float64   = post_new_1 * post_new_2

        # Calculate α, probability of accepting the new particle
        α::Float64 = post_new / post
        if rand() < α
            s_t::AbstractVector{Float64} = s_new
            ϵ_t::AbstractVector{Float64} = ϵ_new
            post = post_new
            accept += 1
        end
    end
    return s_t, ϵ_t, accept
end

"""
```
update_c(c, accept_rate, target_rate)
```

Return the new proposal covariance matrix scaling `c`, adaptively chosen given
`accept_rate` to match `target_rate`.
"""
@inline function update_c(c::Float64, accept_rate::Float64, target_rate::Float64)
    c*(0.95 + 0.1*exp(20*(accept_rate - target_rate))/(1 + exp(20*(accept_rate - target_rate))))
end