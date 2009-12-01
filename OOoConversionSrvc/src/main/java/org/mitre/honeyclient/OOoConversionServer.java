package org.mitre.honeyclient;

import java.io.BufferedReader;
import java.net.ServerSocket;
import java.net.Socket;

import java.io.FileNotFoundException;
import java.io.InputStream;
import java.io.File;
import java.io.IOException;

import java.io.InputStreamReader;
import java.io.OutputStream;
import java.util.Properties;

import org.artofsolving.jodconverter.OfficeDocumentConverter;
import org.artofsolving.jodconverter.office.DefaultOfficeManagerConfiguration;
import org.artofsolving.jodconverter.office.OfficeManager;

import org.codehaus.jackson.map.ObjectMapper;

import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.CommandLineParser;
import org.apache.commons.cli.HelpFormatter;
import org.apache.commons.cli.OptionBuilder;
import org.apache.commons.cli.Options;
import org.apache.commons.cli.ParseException;
import org.apache.commons.cli.PosixParser;

import java.util.logging.Level;
import java.util.logging.Logger;
import org.artofsolving.jodconverter.office.OfficeException;

/**
 * A service for MS Office and the like document conversion
 *
 * @author    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
 * Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
 * License::
 *
 */
public class OOoConversionServer {

    public static final String PARAMETER_OFFICE_PORT = "officePort";
    public static final String PARAMETER_OFFICE_HOME = "officeHome";
    public static final String PARAMETER_OFFICE_PROFILE = "officeProfile";
    public static final String PARAMETER_FILEUPLOAD_MAX_SIZE = "fileUploadMaxSize";
    public static final String PARAMETER_SERVER_PORT = "serverPort";
    private OfficeManager officeManager;
    private OfficeDocumentConverter documentConverter;
    private int serverPort = 0;
    private int fileSizeMax = 0;
    private ServerSocket serverSocket = null;
    private ObjectMapper mapper;

    public static void main(String[] args) throws Exception {

        new OOoConversionServer(args).run();
    }

    public OOoConversionServer(String[] args) throws FileNotFoundException, IOException, ParseException {

        Properties properties = new Properties();

        ClassLoader cl = this.getClass().getClassLoader();
        InputStream inputStream = cl.getResourceAsStream("org/mitre/honeyclient/OOoConversionServer.properties");
        properties.load(inputStream);
        inputStream.close();

        DefaultOfficeManagerConfiguration configuration = new DefaultOfficeManagerConfiguration();

        String officePortParam = properties.getProperty(PARAMETER_OFFICE_PORT);
        String officeHomeParam = properties.getProperty(PARAMETER_OFFICE_HOME);
        String officeProfileParam = properties.getProperty(PARAMETER_OFFICE_PROFILE);
        String serverPortParam = properties.getProperty(PARAMETER_SERVER_PORT);
        String fileSizeMaxParam = properties.getProperty(PARAMETER_FILEUPLOAD_MAX_SIZE);

        CommandLineParser parser = new PosixParser();
        Options options = new Options();

        options.addOption("h", "help", false, "print this message");

        options.addOption(OptionBuilder.withLongOpt(PARAMETER_OFFICE_PORT).withDescription("The port the service listens on.  Default is '" + serverPortParam + "'.").hasArg().withArgName("INTEGER").create());

        options.addOption(OptionBuilder.withLongOpt(PARAMETER_FILEUPLOAD_MAX_SIZE).withDescription("The largest file size that can be uploaded.  Default is '" + fileSizeMaxParam + "'.").hasArg().withArgName("INTEGER").create());

        options.addOption(OptionBuilder.withLongOpt(PARAMETER_OFFICE_PORT).withDescription("The port OpenOffice service daemon will listen on.  Default is '" + officePortParam + "'.").hasArg().withArgName("INTEGER").create());

        options.addOption(OptionBuilder.withLongOpt(PARAMETER_OFFICE_HOME).withDescription("The home directory of OpenOffice.  Default is '" + officeHomeParam + "'.").hasArg().withArgName("PATH").create());

        options.addOption(OptionBuilder.withLongOpt(PARAMETER_OFFICE_PROFILE).withDescription("The profile directory to use for the OpenOffice daemon.  Default is '" + officeProfileParam + "'.").hasArg().withArgName("PATH").create());

        CommandLine cmd = parser.parse(options, args);

        if (cmd.hasOption("h")) {
            HelpFormatter formatter = new HelpFormatter();
            formatter.printHelp("OOoConversionServer", options);
            System.exit(0);
        }

        if (cmd.hasOption(PARAMETER_OFFICE_PORT)) {
            try {
                serverPort = Integer.parseInt(cmd.getOptionValue(PARAMETER_OFFICE_PORT));
            } catch (Exception e) {
                throw new RuntimeException(
                        "serverPort must be an integer value.");
            }
        } else {
            serverPort = Integer.parseInt(serverPortParam);
        }

        if (cmd.hasOption(PARAMETER_FILEUPLOAD_MAX_SIZE)) {
            try {
                fileSizeMax = Integer.parseInt(cmd.getOptionValue(PARAMETER_FILEUPLOAD_MAX_SIZE));
            } catch (Exception e) {
                throw new RuntimeException(
                        "fileSizeMax must be an integer value.");
            }
        } else {
            fileSizeMax = Integer.parseInt(fileSizeMaxParam);
        }

        if (cmd.hasOption(PARAMETER_OFFICE_PORT)) {
            try {
                configuration.setPortNumber(Integer.parseInt(cmd.getOptionValue(PARAMETER_OFFICE_PORT)));
            } catch (Exception e) {
                throw new RuntimeException(
                        "officePort must be an integer value.");
            }
        } else {
            configuration.setPortNumber(Integer.parseInt(officePortParam));
        }

        if (cmd.hasOption(PARAMETER_OFFICE_HOME)) {
            try {
                configuration.setOfficeHome(cmd.getOptionValue(PARAMETER_OFFICE_HOME));
            } catch (Exception e) {
                throw new RuntimeException(
                        "officePath must be a file path.");
            }
        } else {
            configuration.setOfficeHome(new File(officeHomeParam));
        }

        if (cmd.hasOption(PARAMETER_OFFICE_PROFILE)) {
            try {
                configuration.setTemplateProfileDir(new File(cmd.getOptionValue(PARAMETER_OFFICE_PROFILE)));
            } catch (Exception e) {
                throw new RuntimeException(
                        "officePath must be a file path.");
            }
        } else {
            configuration.setTemplateProfileDir(new File(officeProfileParam));
        }

        officeManager = configuration.buildOfficeManager();

        boolean retry = true;
        while (retry) {
            try {
                officeManager.start();
                retry = false;
            } catch (OfficeException e) {

                // little bugger failed to start for whatever reason
                Logger.getLogger(WorkerThread.class.getName()).log(Level.SEVERE, null, e);

                Process p = Runtime.getRuntime().exec("killall office");

                String s = null;

                BufferedReader stdInput = new BufferedReader(new InputStreamReader(p.getInputStream()));

                BufferedReader stdError = new BufferedReader(new InputStreamReader(p.getErrorStream()));

                // read the output from the command
                System.out.println("Here is the standard output of the command:\n");
                while ((s = stdInput.readLine()) != null) {
                    System.out.println(s);
                }

                // read any errors from the attempted command
                System.out.println("Here is the standard error of the command (if any):\n");
                while ((s = stdError.readLine()) != null) {
                    System.out.println(s);
                }

                officeManager = configuration.buildOfficeManager();
                
            }
        }

        documentConverter = new OfficeDocumentConverter(officeManager);

        mapper = new ObjectMapper();

        try {
            serverSocket = new ServerSocket(serverPort);

            Logger.getLogger(WorkerThread.class.getName()).log(Level.INFO, "Listening for clients on " + serverPortParam + "...");

        } catch (IOException e) {
            Logger.getLogger(WorkerThread.class.getName()).log(Level.SEVERE, null, e);
            System.exit(-1);
        }
    }

    public void run() {

        boolean shutdown = false;

        while (!shutdown) {
            try {
                Socket socket = serverSocket.accept();

                if ((socket.getInetAddress().getHostName()).equals("localhost.localdomain")) {
                    WorkerThread workerThread = new WorkerThread(socket, this);
                    workerThread.start();
                } else {

                    try {
                        OutputStream out = socket.getOutputStream();
                        mapper.writeValue(out, new Response("Remote connections not allowed.", null, null));
                    } catch (IOException e) {
                        //swallow
                    }

                }
            } catch (IOException e) {
                Logger.getLogger(WorkerThread.class.getName()).log(Level.SEVERE, null, e);
            }
        }
    }

    public ObjectMapper getMapper() {
        return mapper;
    }

    public int getFileSizeMax() {
        return fileSizeMax;
    }

    public OfficeDocumentConverter getDocumentConverter() {
        return documentConverter;
    }
}
