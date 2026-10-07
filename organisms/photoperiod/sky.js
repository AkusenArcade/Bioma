.pragma library

// Where the sun and the moon stand in the sky of one place, and how much of
// the moon is lit.
//
// The low-precision formulas of Meeus' "Astronomical Algorithms", as the
// ephemerides small enough for a clock use them: the sun to within a minute
// of its rising, the moon to within a fraction of a degree. That is finer than
// a pixel of the organism, and needs no network — only the place's latitude
// and longitude, which the weather has already found.
//
// This file is plain JavaScript with no QML in it, so it can be run and
// checked outside the shell.

const RAD = Math.PI / 180;
const DAY_MS = 86400000;
const J1970 = 2440588;
const J2000 = 2451545;

// The obliquity of the ecliptic.
const OBLIQUITY = RAD * 23.4397;

// The altitude at which the sun's upper limb touches the horizon, refraction
// included: the moment of sunrise and sunset as an almanac gives it.
const HORIZON = -0.833;

function days(ms) {
    return ms / DAY_MS - 0.5 + J1970 - J2000;
}

function rightAscension(l, b) {
    return Math.atan2(Math.sin(l) * Math.cos(OBLIQUITY) - Math.tan(b) * Math.sin(OBLIQUITY), Math.cos(l));
}

function declination(l, b) {
    return Math.asin(Math.sin(b) * Math.cos(OBLIQUITY) + Math.cos(b) * Math.sin(OBLIQUITY) * Math.sin(l));
}

function siderealTime(d, lw) {
    return RAD * (280.16 + 360.9856235 * d) - lw;
}

function sunCoords(d) {
    const m = RAD * (357.5291 + 0.98560028 * d);
    const centre = RAD * (1.9148 * Math.sin(m) + 0.02 * Math.sin(2 * m) + 0.0003 * Math.sin(3 * m));
    const longitude = m + centre + RAD * 102.9372 + Math.PI;
    return { "ra": rightAscension(longitude, 0), "dec": declination(longitude, 0) };
}

function moonCoords(d) {
    const l = RAD * (218.316 + 13.176396 * d);
    const m = RAD * (134.963 + 13.064993 * d);
    const f = RAD * (93.272 + 13.229350 * d);
    const longitude = l + RAD * 6.289 * Math.sin(m);
    const latitude = RAD * 5.128 * Math.sin(f);
    return {
        "ra": rightAscension(longitude, latitude),
        "dec": declination(longitude, latitude),
        "distance": 385001 - 20905 * Math.cos(m)
    };
}

// Altitude above the horizon and compass bearing (0 north, 90 east), both in
// degrees, of a body at the given equatorial coordinates.
function horizontal(coords, d, latitude, longitude) {
    const phi = RAD * latitude;
    const hour = siderealTime(d, RAD * -longitude) - coords.ra;
    const altitude = Math.asin(Math.sin(phi) * Math.sin(coords.dec)
                               + Math.cos(phi) * Math.cos(coords.dec) * Math.cos(hour));
    // Measured from the south, westwards; turned into a bearing from north.
    const azimuth = Math.atan2(Math.sin(hour), Math.cos(hour) * Math.sin(phi) - Math.tan(coords.dec) * Math.cos(phi));
    return {
        "altitude": altitude / RAD,
        "bearing": ((azimuth / RAD + 180) % 360 + 360) % 360
    };
}

function sun(ms, latitude, longitude) {
    const d = days(ms);
    return horizontal(sunCoords(d), d, latitude, longitude);
}

function moon(ms, latitude, longitude) {
    const d = days(ms);
    const coords = moonCoords(d);
    const position = horizontal(coords, d, latitude, longitude);
    // So near a body is seen a little lower from the surface than from the
    // centre of the Earth: up to a degree, at the horizon.
    const parallax = Math.asin(6378 / coords.distance) / RAD;
    position.altitude -= parallax * Math.cos(position.altitude * RAD);
    return position;
}

// How the moon is lit: `fraction` of the disc (0 new, 1 full) and `phase`
// through the month (0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter).
function moonLight(ms) {
    const d = days(ms);
    const s = sunCoords(d);
    const m = moonCoords(d);
    const sunDistance = 149598000;
    const elongation = Math.acos(Math.sin(s.dec) * Math.sin(m.dec)
                                 + Math.cos(s.dec) * Math.cos(m.dec) * Math.cos(s.ra - m.ra));
    const incidence = Math.atan2(sunDistance * Math.sin(elongation), m.distance - sunDistance * Math.cos(elongation));
    const angle = Math.atan2(Math.cos(s.dec) * Math.sin(s.ra - m.ra),
                             Math.sin(s.dec) * Math.cos(m.dec) - Math.cos(s.dec) * Math.sin(m.dec) * Math.cos(s.ra - m.ra));
    return {
        "fraction": (1 + Math.cos(incidence)) / 2,
        "phase": 0.5 + 0.5 * incidence * (angle < 0 ? -1 : 1) / Math.PI
    };
}

// The name of a phase. The four principal ones hold for about a day either
// side of their instant, as a calendar prints them.
function phaseName(phase) {
    const near = 1 / 29.53;
    if (phase < near || phase > 1 - near)
        return "New moon";
    if (Math.abs(phase - 0.25) < near)
        return "First quarter";
    if (Math.abs(phase - 0.5) < near)
        return "Full moon";
    if (Math.abs(phase - 0.75) < near)
        return "Last quarter";
    if (phase < 0.25)
        return "Waxing crescent";
    if (phase < 0.5)
        return "Waxing gibbous";
    if (phase < 0.75)
        return "Waning gibbous";
    return "Waning crescent";
}

// One body's path through a stretch of time, sampled every `step`
// milliseconds: [{ "time", "altitude", "bearing" }].
function path(body, from, to, step, latitude, longitude) {
    const out = [];
    for (let t = from; t <= to; t += step) {
        const p = body(t, latitude, longitude);
        out.push({ "time": t, "altitude": p.altitude, "bearing": p.bearing });
    }
    return out;
}

// The moments a sampled path crosses the horizon: [{ "time", "rising" }],
// each found between two samples by a straight line through them.
function crossings(samples) {
    const out = [];
    for (let i = 1; i < samples.length; i++) {
        const a = samples[i - 1].altitude - HORIZON;
        const b = samples[i].altitude - HORIZON;
        if ((a < 0) === (b < 0))
            continue;
        const k = a / (a - b);
        out.push({
            "time": samples[i - 1].time + k * (samples[i].time - samples[i - 1].time),
            "rising": b > 0
        });
    }
    return out;
}

function daylight(altitude) {
    return altitude > HORIZON;
}
