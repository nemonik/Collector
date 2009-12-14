package org.mitre.honeyclient;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import java.net.Socket;

import java.util.logging.Level;
import java.util.logging.Logger;

import org.apache.commons.codec.binary.Base64;

import org.apache.commons.io.FileUtils;
import org.apache.commons.io.FilenameUtils;

/**
 * A worker thread for processing connections.
 *
 * @author    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
 * Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
 * License::
 * 
 */
class WorkerThread extends Thread {

    private final Socket socket;
    private final OOoConversionServer server;

    public WorkerThread(Socket socket, OOoConversionServer server) {
        this.socket = socket;
        this.server = server;
    }

    @Override
    public void run() {

        Logger.getLogger(WorkerThread.class.getName()).log(Level.INFO, "Accepted a new connection");

        byte[] buf = new byte[1024];
        StringBuffer buffer = new StringBuffer();
        InputStream in = null;
        OutputStream out = null;

        try {

            in = socket.getInputStream();
            out = socket.getOutputStream();

            int len;
            boolean cont = true;

            while (cont) {
                len = in.read(buf);
                buffer.append(new String(buf, 0, len));
                if (buffer.charAt(buffer.length() - 1) == '}') {
                    cont = false;
                }
                Logger.getLogger(WorkerThread.class.getName()).log(Level.INFO, "read: '" + new String(buf, 0, len) + "'");
                Logger.getLogger(WorkerThread.class.getName()).log(Level.INFO, "last charcted read: '" + Character.toString(buffer.charAt(buffer.length() - 1)) + "'");
                Logger.getLogger(WorkerThread.class.getName()).log(Level.INFO, "continue reading on port: " + Boolean.toString(cont));
            }

            String text = buffer.toString();
            File inputFile = null, outputFile = null;
            Response response = null;
            Request request = null;
            byte[] file_bytes;

            try {

                Logger.getLogger(WorkerThread.class.getName()).log(Level.INFO, "request text : " + text);

                request = server.getMapper().readValue(text, Request.class);

                if ((FilenameUtils.getPath(request.getInputFilename()) != null) && (FilenameUtils.getPath(request.getOutputFilename()) != null) && (new File(request.getInputFilename()).exists())) {

                    inputFile = new File(request.getInputFilename());
                    outputFile = new File(request.getOutputFilename());

                } else if (request.getInputBase64FileContents() != null) {

                    file_bytes = Base64.decodeBase64(request.getInputBase64FileContents().getBytes());

                    if (file_bytes.length > server.getFileSizeMax()) {
                        throw new RuntimeException("Fail; File too big to process.");
                    }

                    FileUtils.writeByteArrayToFile(
                            inputFile = File.createTempFile(FilenameUtils.getBaseName(request.getInputFilename()),
                            "." + FilenameUtils.getExtension(request.getInputFilename())),
                            file_bytes);

                    outputFile = File.createTempFile(
                            FilenameUtils.getBaseName(request.getOutputFilename()),
                            "." + FilenameUtils.getExtension(request.getOutputFilename()));

                } else {
                    throw new RuntimeException("No Base64 encoded input file content, nor path provided with input filename.");
                }

                Logger.getLogger(WorkerThread.class.getName()).log(Level.INFO, "calling convert of " + inputFile.getPath() + " to " + outputFile.getPath());

                // TODO: convert using convert(File inputFile, File outputFile, DocumentFormat outputFormat), modify Request to handle
                server.getDocumentConverter().convert(inputFile, outputFile);

                if (request.inputBase64FileContents != null) {
                    byte[] outputFileBytes = new byte[(int) outputFile.length()];
                    FileInputStream f = new FileInputStream(outputFile.getPath());
                    f.read(outputFileBytes, 0, outputFileBytes.length);
                    f.close();

                    String outputBase64encoded = new String(Base64.encodeBase64(outputFileBytes));

                    response = new Response("Success; output returned in Base64 format", request.getOutputFilename(), outputBase64encoded);
                } else {
                    response = new Response("Success; output can found in the output file", request.getOutputFilename(), null);
                }

            } catch (RuntimeException e) {
                Logger.getLogger(WorkerThread.class.getName()).log(Level.SEVERE, e.getMessage());
                response = new Response(e.getMessage(), null, null);
            } catch (java.io.EOFException e) {
                //swallow
            } finally {
                if ((request != null) && (request.getInputBase64FileContents() != null)) {
                    if (inputFile != null) {
                        inputFile.delete();
                    }

                    if (outputFile != null) {
                        outputFile.delete();
                    }
                }

                server.getMapper().writeValue(out, response);
                
            }

        } catch (Exception e) {
            Logger.getLogger(WorkerThread.class.getName()).log(Level.SEVERE, e.getMessage());
        } finally {
            try {
                in.close();
                out.close();
                socket.close();

            } catch (IOException e) {
                Logger.getLogger(WorkerThread.class.getName()).log(Level.SEVERE, null, e);
            }
        }
        Logger.getLogger(WorkerThread.class.getName()).log(Level.INFO, "Done");
    }
}
