# Some methods for validated integration of ODEs

# Stepsize, for Taylor1{TaylorModelN{N,R,T}}
function TaylorIntegration.stepsize(x::Taylor1{TaylorModelN{N,Interval{T},T}},
        epsilon::T) where {N,T<:Real}
    ord = get_order(x)
    h = convert(T, Inf)
    for k in (ord-1, ord)
        @inbounds aux = norm( x[k].pol, Inf)
        (0 ∈ aux) && continue
        aux = epsilon / aux
        kinv = one(T)/k
        aux = aux^kinv
        h = min(h, inf(aux))
    end
    return h
end
#
function TaylorIntegration.stepsize(x::Taylor1{TaylorModelN{N,T,T}},
        epsilon::T) where {N,T<:Real}
    ord = get_order(x)
    h = convert(T, Inf)
    for k in (ord-1, ord)
        @inbounds aux = norm( x[k].pol, Inf)
        (0 ∈ aux) && continue
        aux = epsilon / aux
        kinv = one(T)/k
        aux = aux^kinv
        h = min(h, aux)
    end
    return h
end


"""
    remainder_taylorstep(dx, δI, δt)

Returns a remainder for the integration step using Taylor Models, exploiting
repeated iterations of Schauder's fix point theorem (up to 100) of Picard's
integral operator, considering only the remainder. Inputs are: `dx`, the
vector with the RHS of the defining ODEs, `δI` the interval box where the
initial conditions are varied, and `δt` is the integration interval.
"""
function remainder_taylorstep(dx::Vector{Taylor1{TaylorModelN{N,Interval{T},T}}},
        δI::IntervalBox{N,T}, δt) where {N,T}

    orderT = get_order(dx[1])
    aux = δt^orderT / (orderT+1)
    last_coeffTM = getcoeff.(dx, orderT)
    last_coeff_I = evaluate(last_coeffTM, δI) .* aux
    vv = Vector{Interval{T}}(undef, N)
    Δtest = zero.(δI)

    # This mimics the Schauder's fix point theorem (100 iterations)
    for i = 1:100
        # Only the remainders (Picard's integrationto order orderT) are included
        Δ = δt .* (Δtest .+ last_coeff_I )

        # This enlarges Δtest in all directions, and returns
        if Δ == Δtest
            @inbounds for ind in eachindex(vv)
                vv[ind] = Interval(prevfloat(vv[ind].lo), nextfloat(vv[ind].hi))
            end
            Δtest = IntervalBox(vv)
            return Δtest
        end

        # If needed, the tested remainder is enlarged
        @inbounds for ind in eachindex(vv)
            vv[ind] = Δ[ind]
            (Δ[ind] ⊆ Δtest[ind]) && continue
            vv[ind] = hull(Δ[ind], Δtest[ind])
        end
        Δtest = IntervalBox(vv)
    end

    # NOTE: Return after 100 iterations; this should be changed
    # to ensure convergence. Perhaps shrink δt ?
    @warn("Maximum number of iterations reached")

    return Δtest
end
#
function remainder_taylorstep(dx::Vector{Taylor1{TaylorModelN{N,T,T}}},
        δI::IntervalBox{N,T}, δt) where {N,T}

    orderT = get_order(dx[1])
    aux = δt^orderT / (orderT+1)
    last_coeffTM = getcoeff.(dx, orderT)
    last_coeff_I = evaluate(last_coeffTM, δI) .* aux
    vv = Vector{Interval{T}}(undef, N)
    Δtest = zero.(δI)

    # This mimics the Schauder's fix point theorem (100 iterations)
    for i = 1:100
        # Only the remainders (Picard's integrationto order orderT) are included
        Δ = δt .* (Δtest .+ last_coeff_I )

        # This enlarges Δtest in all directions, and returns
        if Δ == Δtest
            @inbounds for ind in eachindex(vv)
                vv[ind] = Interval(prevfloat(vv[ind].lo), nextfloat(vv[ind].hi))
            end
            Δtest = IntervalBox(vv)
            return Δtest
        end

        # If needed, the tested remainder is enlarged
        @inbounds for ind in eachindex(vv)
            vv[ind] = Δ[ind]
            (Δ[ind] ⊆ Δtest[ind]) && continue
            vv[ind] = hull(Δ[ind], Δtest[ind])
        end
        Δtest = IntervalBox(vv)
    end

    # NOTE: Return after 100 iterations; this should be changed
    # to ensure convergence. Perhaps shrink δt ?
    @warn("Maximum number of iterations reached")

    return Δtest
end


function TaylorIntegration.taylorstep!(f!, t::Taylor1{R},
        x::Vector{Taylor1{TaylorModelN{N,R,T}}},
        dx::Vector{Taylor1{TaylorModelN{N,R,T}}},
        xaux::Vector{Taylor1{TaylorModelN{N,R,T}}},
        t0::T, t1::T,
        orderT::Int, abstol::T,
        parse_eqs::Bool=true) where {N,R,T<:Real}

    @assert t1 > t0

    # Compute the Taylor coefficients (non-validated integration)
    TaylorIntegration.__jetcoeffs!(Val(parse_eqs), f!, t, x, dx, xaux)

    # Compute the step-size of the integration using `abstol`
    δt = TaylorIntegration.stepsize(x, abstol)
    δt = min(δt, t1-t0)

    return δt
end

function validated_integ(f!, q0::IntervalBox{N,T}, δq0::IntervalBox{N,T},
        t0::T, tmax::T, orderQ::Int, orderT::Int, abstol::T;
        maxsteps::Int=500, parse_eqs::Bool=true, sym_norm::Bool=true) where {N, T<:Real}

    # Set proper parameters for jet transport
    @assert N == get_numvars()
    dof = N
    if get_order() != 2*orderQ
        set_variables("δ", numvars=dof, order=2*orderQ)
    end

    # Some variables
    R   = Interval{T}
    ti0 = Interval(t0)
    t   = ti0 + Taylor1(orderT)
    δq_norm = sym_norm ? IntervalBox(-1..1, Val(N)) : IntervalBox(0..1, Val(N))

    # Allocation of vectors
    # Output
    tv    = Array{T}(undef, maxsteps+1)
    xv    = Array{IntervalBox{N,T}}(undef, maxsteps+1)
    xTMNv = Array{TaylorModelN{N,R,T}}(undef, dof, maxsteps+1)
    # Internals
    x     = Array{Taylor1{TaylorModelN{N,R,T}}}(undef, dof)
    dx    = Array{Taylor1{TaylorModelN{N,R,T}}}(undef, dof)
    xaux  = Array{Taylor1{TaylorModelN{N,R,T}}}(undef, dof)
    xTMN  = Array{TaylorModelN{N,R,T}}(undef, dof)

    # Set initial conditions
    zI = zero(R)
    @inbounds for i in eachindex(x)
        qaux = normalize_taylor(q0[i] + TaylorN(i, order=orderQ), δq0, sym_norm)
        x[i] = Taylor1( TaylorModelN(qaux, zI, q0, q0 + δq_norm), orderT )
        dx[i] = x[i]
        xTMN[i] = x[i][0]
    end

    # Output vectors
    @inbounds tv[1] = t0
    @inbounds xv[1] = IntervalBox( evaluate(xTMN, δq_norm) )
    @inbounds xTMNv[:,1] .= xTMN

    # Determine if specialized jetcoeffs! method exists (built by @taylorize)
    parse_eqs = parse_eqs && (length(methods(TaylorIntegration.jetcoeffs!)) > 2)
    if parse_eqs
        try
            TaylorIntegration.jetcoeffs!(Val(f!), t, x, dx)
        catch
            parse_eqs = false
        end
    end

    # Integration
    nsteps = 1
    while t0 < tmax
        # One step integration (non-validated)
        δt = TaylorIntegration.taylorstep!(f!, t, x, dx, xaux,
            t0, tmax, orderT, abstol, parse_eqs)

        # Validate the solution: build a tight remainder (based on Schauder thm)
        # This is to compute dx[:][orderT] (now zero), needed for the remainder
        f!(t, x, dx)
        Δ = remainder_taylorstep(dx, δq_norm, Interval(0.0,δt)) # remainder of integration step
        # @assert all(0..0 .⊆ Δ)

        # Evaluate the solution (TaylorModelN) at δt including remainder Δ
        # New initial conditions and output
        t0 += δt
        nsteps += 1
        @inbounds begin
            for i in eachindex(x)
                tmp1 = evaluate(x[i], Interval(0,δt))
                xTMNv[i,nsteps] = TaylorModelN(tmp1.pol, tmp1.rem + Δ[i], tmp1.x0, tmp1.I)
                tmp = evaluate( x[i], δt )
                xTMN[i] = TaylorModelN(tmp.pol, tmp.rem + Δ[i], tmp.x0, tmp.I)
                x[i]  = Taylor1( xTMN[i], orderT )
                dx[i] = Taylor1( zero(xTMN[i]), orderT )
            end
            t[0] = Interval(t0)
            tv[nsteps] = t0
            xv[nsteps] = evaluate(xTMNv[:,nsteps], δq_norm)
        end
        # println(nsteps, "\t", t0, "\t", x0, "\t", diam(Δ))
        if nsteps > maxsteps
            @info("""
            Maximum number of integration steps reached; exiting.
            """)
            break
        end
    end

    return view(tv,1:nsteps), view(xv,1:nsteps)
    # return view(tv,1:nsteps), view(transpose(view(xTMNv,:,1:nsteps)),1:nsteps,:)
end
#
function validated_integ(f!, qq0::AbstractArray{T,1}, δq0::IntervalBox{N,T},
        t0::T, tmax::T, orderQ::Int, orderT::Int, abstol::T;
        maxsteps::Int=500, parse_eqs::Bool=true, sym_norm::Bool=true) where {N, T<:Real}

    # Set proper parameters for jet transport
    @assert N == get_numvars()
    dof = N
    if get_order() != 2*orderQ
        set_variables("δ", numvars=dof, order=2*orderQ)
    end

    # Some variables
    R   = Interval{T}
    q0 = IntervalBox(Interval.(qq0))
    t   = t0 + Taylor1(orderT)
    δq_norm = sym_norm ? IntervalBox(-1..1, Val(N)) : IntervalBox(0..1, Val(N))

    # Allocation of vectors
    # Output
    tv    = Array{T}(undef, maxsteps+1)
    xv    = Array{IntervalBox{N,T}}(undef, maxsteps+1)
    xTMNv = Array{TaylorModelN{N,T,T}}(undef, dof, maxsteps+1)
    # Internals
    x     = Array{Taylor1{TaylorModelN{N,T,T}}}(undef, dof)
    dx    = Array{Taylor1{TaylorModelN{N,T,T}}}(undef, dof)
    xaux  = Array{Taylor1{TaylorModelN{N,T,T}}}(undef, dof)
    xTMN  = Array{TaylorModelN{N,T,T}}(undef, dof)

    # Set initial conditions
    zI = zero(R)
    @inbounds for i in eachindex(x)
        qaux = normalize_taylor(qq0[i] + TaylorN(i, order=orderQ), δq0, sym_norm)
        x[i] = Taylor1( TaylorModelN(qaux, zI, q0, q0 + δq_norm), orderT)
        dx[i] = x[i]
        xTMN[i] = x[i][0]
    end

    # Output vectors
    @inbounds tv[1] = t0
    @inbounds xv[1] = IntervalBox( evaluate(xTMN, δq_norm) )
    @inbounds xTMNv[:,1] .= xTMN

    # Determine if specialized jetcoeffs! method exists (built by @taylorize)
    parse_eqs = parse_eqs && (length(methods(TaylorIntegration.jetcoeffs!)) > 2)
    if parse_eqs
        try
            TaylorIntegration.jetcoeffs!(Val(f!), t, x, dx)
        catch
            parse_eqs = false
        end
    end

    # Integration
    nsteps = 1
    while t0 < tmax
        # One step integration (non-validated)
        δt = TaylorIntegration.taylorstep!(f!, t, x, dx, xaux,
            t0, tmax, orderT, abstol, parse_eqs)

        # Validate the solution: build a tight remainder (based on Schauder thm)
        # This is to compute dx[:][orderT] (now zero), needed for the remainder
        f!(t, x, dx)
        Δ = remainder_taylorstep(dx, δq_norm, Interval(0.0,δt)) # remainder of integration step
        # @assert all(0..0 .⊆ Δ)

        # Evaluate the solution (TaylorModelN) at δt including remainder Δ
        # New initial conditions and output
        t0 += δt
        nsteps += 1
        @inbounds begin
            for i in eachindex(x)
                tmp1 = fp_rpa( evaluate(x[i], Interval(0,δt)) )
                xTMNv[i,nsteps] = TaylorModelN(tmp1.pol, tmp1.rem + Δ[i], tmp1.x0, tmp1.I)
                tmp = evaluate( x[i], δt )
                xTMN[i] = TaylorModelN(tmp.pol, tmp.rem+Δ[i], tmp.x0, tmp.I)
                x[i]  = Taylor1( xTMN[i], orderT )
                dx[i] = Taylor1( zero(xTMN[i]), orderT )
            end
            t[0] = t0
            tv[nsteps] = t0
            xv[nsteps] = evaluate(xTMNv[:,nsteps], δq_norm)
        end
        # println(nsteps, "\t", t0, "\t", x0, "\t", diam(Δ))
        if nsteps > maxsteps
            @info("""
            Maximum number of integration steps reached; exiting.
            """)
            break
        end
    end

    return view(tv,1:nsteps), view(xv,1:nsteps)
    # return view(tv,1:nsteps), view(transpose(view(xTMNv,:,1:nsteps)),1:nsteps,:)
end
