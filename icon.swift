import Cocoa
let image = NSImage(size:NSSize(width:1024,height:1024)); image.lockFocus()
NSColor(calibratedRed:0.06,green:0.13,blue:0.23,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:32,y:32,width:960,height:960),xRadius:220,yRadius:220).fill()
let gradient = NSGradient(starting:NSColor(calibratedRed:0.1,green:0.85,blue:0.88,alpha:1),ending:NSColor(calibratedRed:0.23,green:0.4,blue:0.95,alpha:1))!
let drop = NSBezierPath(); drop.move(to:NSPoint(x:512,y:850)); drop.curve(to:NSPoint(x:260,y:420),controlPoint1:NSPoint(x:450,y:720),controlPoint2:NSPoint(x:260,y:570)); drop.curve(to:NSPoint(x:764,y:420),controlPoint1:NSPoint(x:250,y:70),controlPoint2:NSPoint(x:774,y:70)); drop.curve(to:NSPoint(x:512,y:850),controlPoint1:NSPoint(x:764,y:570),controlPoint2:NSPoint(x:574,y:720)); drop.close(); gradient.draw(in:drop,angle:-90)
NSColor.white.withAlphaComponent(0.9).setStroke(); let wave = NSBezierPath(); wave.lineWidth=28; wave.lineCapStyle = .round
wave.move(to:NSPoint(x:355,y:420)); wave.curve(to:NSPoint(x:670,y:420),controlPoint1:NSPoint(x:460,y:530),controlPoint2:NSPoint(x:570,y:310)); wave.stroke()
image.unlockFocus(); let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!; try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
