pragma Singleton

import QtQuick
import Quickshell

// Region trees, built at runtime.
//
// A window's input mask and its `ext-background-effect` blur region are both
// `Region` trees, and both have to follow a cell list that changes while the
// shell runs. Quickshell's `Region.regions` is a read-only list filled by QML's
// default-property mechanism: an object created with `Qt.createQmlObject` or
// `Component.createObject` and given a Region as its QObject parent does **not**
// join it — verified, the list stays empty.
//
// So the tree is built from a QML string containing the children, which does
// work, and the leaves are then bound by hand. Only the child count requires a
// rebuild; item geometry follows the item, and radii are reassigned in place.
Singleton {
    id: root

    // A Region with `count` empty children, owned by `owner`. The caller keeps
    // the result and destroys the previous one when the count changes.
    function tree(owner, count) {
        const children = new Array(Math.max(0, count)).fill("  Region {}").join("\n");
        return Qt.createQmlObject(`import Quickshell\nRegion {\n${children}\n}`, owner);
    }

    // `shapes` is a list of { item, radius }. Returns true when the tree
    // matched the shape list and was bound.
    function bind(region, shapes) {
        if (!region || region.regions.length !== shapes.length)
            return false;
        for (let i = 0; i < shapes.length; i++) {
            const leaf = region.regions[i];
            leaf.item = shapes[i].item;
            leaf.radius = Math.round(shapes[i].radius);
        }
        return true;
    }

    // The same, inverted: everything of `base` except the shapes. This is what
    // a full-screen catcher wants — the screen minus every surface the shell
    // already claims — so that its input region and the membranes' never
    // overlap and the stacking order stops mattering.
    function hole(owner, count) {
        const children = new Array(Math.max(0, count))
            .fill("  Region { intersection: Intersection.Subtract }")
            .join("\n");
        return Qt.createQmlObject(`import Quickshell\nRegion {\n${children}\n}`, owner);
    }

    // The same shapes as plain rectangles rather than as items. A region belongs
    // to one surface and an item to another: asked where it is, an item answers
    // in the coordinates of *its own* window, and two surfaces that do not share
    // an origin — a membrane on the bottom edge and a catcher over the whole
    // screen — do not mean the same point by the same numbers.
    function bindRects(region, rects) {
        if (!region || region.regions.length !== rects.length)
            return false;
        for (let i = 0; i < rects.length; i++) {
            const leaf = region.regions[i];
            leaf.item = null;
            leaf.x = Math.round(rects[i].x);
            leaf.y = Math.round(rects[i].y);
            leaf.width = Math.round(rects[i].width);
            leaf.height = Math.round(rects[i].height);
            leaf.radius = Math.round(rects[i].radius);
        }
        return true;
    }

    function rebindHoleRects(owner, previous, base, rects) {
        let region = previous;
        if (!region || region.regions.length !== rects.length) {
            if (region)
                region.destroy();
            region = root.hole(owner, rects.length);
        }
        region.item = base;
        root.bindRects(region, rects);
        return region;
    }

    function rebindHoles(owner, previous, base, shapes) {
        let region = previous;
        if (!region || region.regions.length !== shapes.length) {
            if (region)
                region.destroy();
            region = root.hole(owner, shapes.length);
        }
        region.item = base;
        root.bind(region, shapes);
        return region;
    }

    // Rebuilds only when the count changed, binds either way. `previous` is
    // destroyed when it is replaced.
    function rebind(owner, previous, shapes) {
        let region = previous;
        if (!region || region.regions.length !== shapes.length) {
            if (region)
                region.destroy();
            region = root.tree(owner, shapes.length);
        }
        root.bind(region, shapes);
        return region;
    }
}
