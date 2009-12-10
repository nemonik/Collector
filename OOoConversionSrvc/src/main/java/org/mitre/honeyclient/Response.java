package org.mitre.honeyclient;

import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * A POJO used for JSON-based response
 *
 * @author    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
 * Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
 * License::
 *
 */
public class Response {

    String msg;
    String outputFilename;
    String outputBase64FileContents;

    public Response(String msg, String outputFilename, String outputBase64FileContents) {
        this.msg = msg;
        this.outputFilename = outputFilename;
        this.outputBase64FileContents = outputBase64FileContents;

        Logger.getLogger(Response.class.getName()).log(Level.INFO, "Created: " + toString());
    }

    public String getMsg() {
        return msg;
    }

    public void setMsg(String msg) {
        this.msg = msg;
    }

    public String getOutputBase64FileContents() {
        return outputBase64FileContents;
    }

    public void setOutputBase64FileContents(String outputBase64FileContents) {
        this.outputBase64FileContents = outputBase64FileContents;
    }

    public String getOutputFilename() {
        return outputFilename;
    }

    public void setOutputFilename(String outputFilename) {
        this.outputFilename = outputFilename;
    }

    @Override
    public String toString() {
        return "Response [" + "msg=" + (msg == null ? "null" : "\"" + msg + "\"") + ", " + "outputBase64FileContents=" +  (outputBase64FileContents == null ? "null" : "\"" + outputBase64FileContents + "\"") + ", " + "outputFilename=" + (outputFilename == null ? "null" : "\"" + outputFilename + "\"") + "]";
    }
}
