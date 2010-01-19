/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package org.mitre.honeyclient;

import java.io.File;
import org.artofsolving.jodconverter.StandardConversionTask;
import org.artofsolving.jodconverter.document.DocumentFormat;

/**
 *
 * @author    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
 * Copyright:: Copyright (c) 2010 The MITRE Corporation.  All Rights Reserved.
 * License:: GNU GENERAL PUBLIC LICENSE
 */
public class ServerConversionTask extends StandardConversionTask {

    private final Object worker;

    public ServerConversionTask(File inputFile, File outputFile, DocumentFormat outputFormat, Object worker) {
        super(inputFile, outputFile, outputFormat);
        
        this.worker = worker;
    }

    public void notifyWorker() {
        synchronized(worker) {
            worker.notify();
        }
    }

    String getWorkerName() {
        return ((Thread) worker).getName();
    }
}
