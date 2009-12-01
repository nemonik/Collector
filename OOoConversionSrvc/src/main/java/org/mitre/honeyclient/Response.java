/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package org.mitre.honeyclient;

/**
 *
 * @author walsh
 */
public class Response {

    String msg;
    String outputFilename;
    String outputBase64FileContents;

    public Response(String msg, String outputFilename, String outputBase64FileContents) {
        this.msg = msg;
        this.outputFilename = outputFilename;
        this.outputBase64FileContents = outputBase64FileContents;
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


}
