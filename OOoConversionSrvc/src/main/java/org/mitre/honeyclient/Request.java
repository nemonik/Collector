package org.mitre.honeyclient;

/**
 * A POJO used for JSON-based request
 *
 * @author    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
 * Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
 * License::
 *
 */
public class Request {

    String outputFormat;
    String outputFilename;
    String inputFilename;
    String inputBase64FileContents;

    public String getInputBase64FileContents() {
        return inputBase64FileContents;
    }

    public void setInputBase64FileContents(String inputBase64FileContents) {
        this.inputBase64FileContents = inputBase64FileContents;
    }

    public String getInputFilename() {
        return inputFilename;
    }

    public void setInputFilename(String inputFilename) {
        this.inputFilename = inputFilename;
    }

    public String getOutputFilename() {
        return outputFilename;
    }

    public void setOutputFilename(String outputFilename) {
        this.outputFilename = outputFilename;
    }

    public String getOutputFormat() {
        return outputFormat;
    }

    public void setOutputFormat(String outputFormat) {
        this.outputFormat = outputFormat;
    }
}
