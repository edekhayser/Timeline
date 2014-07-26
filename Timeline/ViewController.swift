//
//  ViewController.swift
//  Timeline
//
//  Created by Evan Dekhayser on 7/26/14.
//  Copyright (c) 2014 Evan Dekhayser. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
                            
    var scrollView: UIScrollView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        scrollView = UIScrollView(frame: view.bounds)
        view.addSubview(scrollView)
        
        let timeline = TimelineView(width: scrollView.frame.size.width, timeFrames: [
            TimeFrame(date: "January 1", text: "New Year's Day", image: UIImage(named: "fireworks.png")),
            TimeFrame(date: "February 14", text: "The month of love!", image: UIImage(named: "heart.png")),
            TimeFrame(date: "March", text: "Comes like a lion, leaves like a lamb", image: nil),
            TimeFrame(date: "April 1", text: "Dumb pranks that mean nothing", image: UIImage(named: "april.png")),
            TimeFrame(date: "No image?", text: "That's right. No image is necessary!", image: nil),
            TimeFrame(date: "Long text",text: "This control can stretch. It doesn't matter how long or short the text is, or how many times you wiggle your nose and make a wish. The control always fits the content, and even extends a while at the end so the scroll view it is put into, even when pulled pretty far down, does not show the end of the scroll view.", image: nil),
            TimeFrame(date: "That's is!", text: "Hope this helps someone!", image: nil)
            ])
        scrollView.addSubview(timeline)
        scrollView.contentSize = CGSize(width: timeline.frame.size.width, height: timeline.frame.size.height)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

